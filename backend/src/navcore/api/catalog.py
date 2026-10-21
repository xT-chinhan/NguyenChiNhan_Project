import asyncio
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request
from pydantic import ValidationError

from navcore.api.auth import admin, principal
from navcore.api.errors import ApiError
from navcore.runtime.worker import WorkerBusy, WorkerFault
from navcore.schemas.catalog import (
    CheckpointMetadata,
    Empty,
    MapView,
    Named,
    PlaceView,
    RouteCreate,
    RouteView,
)
from navcore.storage import catalog
from navcore.storage.database import complete_thread

router = APIRouter(prefix="/v1")


def require_vision(app):
    if app.state.vision is None or app.state.worker.check_fault():
        raise ApiError("VISION_UNAVAILABLE", 503, "Vision is unavailable")
    return app.state.vision


def catalog_available(app):
    registry = getattr(app.state, "sessions", None)
    if registry is not None and registry.active_count():
        raise ApiError("CATALOG_BUSY", 409, "Catalog is busy with active navigation")


async def mutation(app, function, *args):
    async with app.state.admission_lock:
        catalog_available(app)
        return await complete_thread(function, app.state.engine, *args)


@router.post("/admin/maps", status_code=201, response_model=MapView, dependencies=[Depends(admin)])
async def create_map(values: Named, request: Request):
    return await mutation(request.app, catalog.create_map, values.name)


@router.post(
    "/admin/maps/{map_id}/places",
    status_code=201,
    response_model=PlaceView,
    dependencies=[Depends(admin)],
)
async def create_place(map_id: UUID, values: Named, request: Request):
    return await mutation(request.app, catalog.create_place, map_id, values.name)


@router.post(
    "/admin/routes", status_code=201, response_model=RouteView, dependencies=[Depends(admin)]
)
async def create_route(values: RouteCreate, request: Request):
    vision = request.app.state.vision
    fingerprint = vision.encoder_fingerprint if vision else None
    return await mutation(request.app, catalog.create_route, values, fingerprint)


@router.post("/admin/routes/{route_id}/checkpoints", status_code=201, dependencies=[Depends(admin)])
async def add_checkpoint(route_id: UUID, request: Request):
    from navcore.vision.images import canonical_reference

    app = request.app
    async with app.state.admission_lock:
        catalog_available(app)
        await asyncio.to_thread(catalog.draft_info, app.state.engine, route_id)
        vision = require_vision(app)
        form = await request.form(max_files=8, max_fields=1, max_part_size=4 * 1024 * 1024)
        try:
            if set(form.keys()) != {"metadata", "images"} or len(form.getlist("metadata")) != 1:
                raise ApiError("VALIDATION_ERROR", 422, "Expected metadata and images")
            try:
                metadata = CheckpointMetadata.model_validate_json(form["metadata"])
            except (ValidationError, TypeError):
                raise ApiError("VALIDATION_ERROR", 422, "Invalid checkpoint metadata") from None
            uploads = form.getlist("images")
            if not 3 <= len(uploads) <= 8:
                raise ApiError("VALIDATION_ERROR", 422, "Expected 3..8 images")
            references = []
            for upload in uploads:
                if not hasattr(upload, "read"):
                    raise ApiError("IMAGE_INVALID", 422, "Expected image files")
                data = await upload.read(393217)
                if len(data) > 393216:
                    raise ApiError("PAYLOAD_TOO_LARGE", 413, "Image is too large")
                try:
                    image = await asyncio.to_thread(canonical_reference, data)
                    vector = await app.state.worker.run(vision.encode, image.rgb)
                except (WorkerBusy, WorkerFault):
                    raise ApiError("VISION_UNAVAILABLE", 503, "Vision is unavailable") from None
                except (ValueError, OSError):
                    raise ApiError("IMAGE_INVALID", 422, "Invalid image") from None
                references.append((image, vector))
            return await complete_thread(
                catalog.add_checkpoint,
                app.state.engine,
                route_id,
                metadata,
                references,
                vision.encoder_fingerprint,
            )
        finally:
            await form.close()


@router.post(
    "/admin/routes/{route_id}/publish", response_model=RouteView, dependencies=[Depends(admin)]
)
async def publish_route(route_id: UUID, values: Empty, request: Request):
    app = request.app
    async with app.state.admission_lock:
        existing = await asyncio.to_thread(catalog.detail, app.state.engine, route_id)
        if existing["status"] == "published":
            return RouteView.model_validate({key: existing[key] for key in RouteView.model_fields})
        catalog_available(app)
        vision = require_vision(app)
        return await complete_thread(
            catalog.publish, app.state.engine, route_id, vision.encoder_fingerprint
        )


@router.get("/admin/routes/{route_id}", dependencies=[Depends(admin)])
async def route_detail(route_id: UUID, request: Request):
    vision = request.app.state.vision
    return await asyncio.to_thread(
        catalog.detail,
        request.app.state.engine,
        route_id,
        vision.encoder_fingerprint if vision else None,
    )


@router.get("/maps", dependencies=[Depends(principal)])
async def maps(
    request: Request, cursor: UUID | None = None, limit: Annotated[int, Query(ge=1, le=100)] = 50
):
    return await asyncio.to_thread(catalog.page, request.app.state.engine, "maps", cursor, limit)


@router.get("/maps/{map_id}/places", dependencies=[Depends(principal)])
async def places(
    map_id: UUID,
    request: Request,
    cursor: UUID | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
):
    return await asyncio.to_thread(
        catalog.page, request.app.state.engine, "places", cursor, limit, map_id
    )


@router.get("/routes", dependencies=[Depends(principal)])
async def routes(map_id: UUID, from_place_id: UUID, to_place_id: UUID, request: Request):
    return await asyncio.to_thread(
        catalog.routes, request.app.state.engine, map_id, from_place_id, to_place_id
    )
