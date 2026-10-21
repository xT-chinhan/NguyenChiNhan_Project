"""Transactional catalog operations; no ORM objects cross the thread seam."""

import math
import struct
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from navcore.api.errors import ApiError
from navcore.core.types import Action, Reference, RouteSnapshot
from navcore.core.types import Checkpoint as CoreCheckpoint
from navcore.storage.database import transaction
from navcore.storage.models import Checkpoint, Map, Place, ReferenceImage, Route


def pack_vector(vector) -> bytes:
    values = tuple(float(value) for value in vector)
    if len(values) != 768 or not all(math.isfinite(v) for v in values):
        raise ValueError("Embedding must contain 768 finite values")
    if abs(math.sqrt(sum(v * v for v in values)) - 1) > 1e-4:
        raise ValueError("Embedding must be L2-normalized")
    return struct.pack("<768f", *values)


def unpack_vector(data: bytes) -> tuple[float, ...]:
    if len(data) != 3072:
        raise ValueError("Stored embedding byte length is invalid")
    values = struct.unpack("<768f", data)
    pack_vector(values)
    return values


def fields(row, *names):
    return {name: getattr(row, name) for name in names}


def map_view(row):
    return fields(row, "id", "name", "created_at")


def place_view(row):
    return fields(row, "id", "map_id", "name", "created_at")


def route_view(row):
    return fields(
        row,
        "id",
        "map_id",
        "name",
        "from_place_id",
        "to_place_id",
        "revision",
        "status",
        "encoder_fingerprint",
        "route_fingerprint",
        "created_at",
        "published_at",
    )


def required(session, model, identifier, *, lock=False):
    row = session.get(model, identifier, with_for_update=lock)
    if row is None:
        raise ApiError("RESOURCE_NOT_FOUND", 404, "Resource not found")
    return row


def create_map(engine, name):
    with transaction(engine) as session:
        row = Map(name=name)
        session.add(row)
        session.flush()
        return map_view(row)


def create_place(engine, map_id, name):
    try:
        with transaction(engine) as session:
            required(session, Map, map_id)
            row = Place(map_id=map_id, name=name, name_key=" ".join(name.split()).casefold())
            session.add(row)
            session.flush()
            return place_view(row)
    except IntegrityError:
        raise ApiError("VALIDATION_ERROR", 422, "Place name already exists in map") from None


def create_route(engine, values, encoder_fingerprint=None):
    with transaction(engine) as session:
        required(session, Map, values.map_id, lock=True)
        for identifier in (values.from_place_id, values.to_place_id):
            place = required(session, Place, identifier)
            if place.map_id != values.map_id:
                raise ApiError("VALIDATION_ERROR", 422, "Route endpoints must belong to map")
        revision = (
            session.scalar(
                select(func.max(Route.revision)).where(
                    Route.map_id == values.map_id,
                    Route.from_place_id == values.from_place_id,
                    Route.to_place_id == values.to_place_id,
                )
            )
            or 0
        )
        row = Route(
            **values.model_dump(), revision=revision + 1, encoder_fingerprint=encoder_fingerprint
        )
        session.add(row)
        session.flush()
        return route_view(row)


def page(engine, kind, cursor=None, limit=50, map_id=None):
    model, view = (Map, map_view) if kind == "maps" else (Place, place_view)
    with transaction(engine) as session:
        query = select(model).order_by(model.id).limit(limit + 1)
        if map_id is not None:
            required(session, Map, map_id)
            query = query.where(Place.map_id == map_id)
        if cursor is not None:
            query = query.where(model.id > cursor)
        rows = session.scalars(query).all()
        return {
            "items": [view(row) for row in rows[:limit]],
            "next_cursor": str(rows[limit - 1].id) if len(rows) > limit else None,
        }


def routes(engine, map_id, from_place_id, to_place_id):
    with transaction(engine) as session:
        rows = session.scalars(
            select(Route)
            .where(
                Route.map_id == map_id,
                Route.from_place_id == from_place_id,
                Route.to_place_id == to_place_id,
                Route.status == "published",
            )
            .order_by(Route.revision.desc())
            .limit(20)
        )
        return {"items": [route_view(row) for row in rows]}


def snapshot(session, row) -> RouteSnapshot:
    checkpoints = []
    for point in session.scalars(
        select(Checkpoint).where(Checkpoint.route_id == row.id).order_by(Checkpoint.seq)
    ):
        refs = tuple(
            Reference(
                str(ref.id),
                ref.pixel_sha256,
                unpack_vector(ref.embedding),
                ref.encoder_fingerprint,
                ref.jpeg_bytes,
                ref.source_group,
            )
            for ref in session.scalars(
                select(ReferenceImage)
                .where(ReferenceImage.checkpoint_id == point.id)
                .order_by(ReferenceImage.id)
            )
        )
        checkpoints.append(
            CoreCheckpoint(
                str(point.id),
                point.seq,
                Action(point.depart_action),
                point.landmark,
                point.heading_deg,
                point.heading_accuracy_deg,
                refs,
            )
        )
    return RouteSnapshot(
        str(row.id),
        row.revision,
        row.encoder_fingerprint,
        row.route_fingerprint,
        tuple(checkpoints),
    )


def load_published(engine, route_id, encoder_fingerprint):
    with transaction(engine) as session:
        row = required(session, Route, route_id)
        if row.status != "published":
            raise ApiError("ROUTE_NOT_PUBLISHED", 409, "Route is not published")
        if row.encoder_fingerprint != encoder_fingerprint:
            raise ApiError("MODEL_FINGERPRINT_MISMATCH", 409, "Route uses a different encoder")
        return snapshot(session, row)


def add_checkpoint(engine, route_id, metadata, references, encoder_fingerprint):
    try:
        with transaction(engine) as session:
            row = required(session, Route, route_id, lock=True)
            if row.status != "draft":
                raise ApiError("ROUTE_IMMUTABLE", 409, "Published route is immutable")
            if row.encoder_fingerprint not in (None, encoder_fingerprint):
                raise ApiError("MODEL_FINGERPRINT_MISMATCH", 409, "Route uses a different encoder")
            row.encoder_fingerprint = encoder_fingerprint
            point = Checkpoint(route_id=route_id, **metadata.model_dump(exclude={"source_group"}))
            session.add(point)
            session.flush()
            for image, vector in references:
                height, width = image.rgb.shape[:2]
                session.add(
                    ReferenceImage(
                        checkpoint_id=point.id,
                        jpeg_bytes=image.jpeg_bytes,
                        width=width,
                        height=height,
                        pixel_sha256=image.pixel_sha256,
                        source_group=metadata.source_group,
                        embedding=pack_vector(vector),
                        encoder_fingerprint=encoder_fingerprint,
                    )
                )
            session.flush()
            return {
                "id": point.id,
                "route_id": route_id,
                "seq": point.seq,
                "depart_action": point.depart_action,
                "landmark": point.landmark,
                "heading_deg": point.heading_deg,
                "heading_accuracy_deg": point.heading_accuracy_deg,
                "reference_count": len(references),
            }
    except IntegrityError:
        raise ApiError("ROUTE_INVALID", 422, "Duplicate checkpoint or image") from None


def draft_info(engine, route_id):
    with transaction(engine) as session:
        row = required(session, Route, route_id)
        if row.status != "draft":
            raise ApiError("ROUTE_IMMUTABLE", 409, "Published route is immutable")
        return route_view(row)


def detail(engine, route_id, encoder_fingerprint=None):
    from navcore.core.routes import validate_route

    with transaction(engine) as session:
        row = required(session, Route, route_id)
        data = route_view(row)
        data["checkpoints"] = [
            fields(
                point,
                "id",
                "seq",
                "depart_action",
                "landmark",
                "heading_deg",
                "heading_accuracy_deg",
            )
            for point in session.scalars(
                select(Checkpoint).where(Checkpoint.route_id == row.id).order_by(Checkpoint.seq)
            )
        ]
        data["publish_errors"] = []
        if row.status == "draft":
            try:
                validate_route(
                    snapshot(session, row), encoder_fingerprint or row.encoder_fingerprint
                )
            except ValueError as error:
                data["publish_errors"] = [
                    {
                        "code": getattr(error, "code", "ROUTE_INVALID"),
                        "details": getattr(error, "details", []),
                    }
                ]
        return data


def publish(engine, route_id, encoder_fingerprint):
    from navcore.core.routes import validate_route

    with transaction(engine) as session:
        row = required(session, Route, route_id, lock=True)
        if row.status == "published":
            return route_view(row)
        metadata = {
            key: str(value)
            for key, value in fields(
                row, "id", "name", "map_id", "from_place_id", "to_place_id", "revision"
            ).items()
        }
        try:
            route = snapshot(session, row)
            fingerprint = validate_route(route, encoder_fingerprint, metadata=metadata)
        except ValueError as error:
            code = getattr(error, "code", "ROUTE_INVALID")
            raise ApiError(
                code,
                409 if code == "MODEL_FINGERPRINT_MISMATCH" else 422,
                "Route cannot be published",
                getattr(error, "details", []),
            ) from None
        row.route_fingerprint = fingerprint
        row.status = "published"
        row.published_at = datetime.now(UTC)
        session.flush()
        return route_view(row)
