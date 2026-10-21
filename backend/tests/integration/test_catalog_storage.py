import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from navcore.api.errors import ApiError
from navcore.schemas.catalog import RouteCreate
from navcore.storage import catalog
from navcore.storage.database import transaction
from navcore.storage.models import Checkpoint, Map, Place, ReferenceImage, Route


def test_cross_map_rejected_by_database_even_without_http(engine):
    with transaction(engine) as session:
        first, second = Map(name="A"), Map(name="B")
        session.add_all([first, second])
        session.flush()
        a, b = (
            Place(map_id=first.id, name="Một", name_key="một"),
            Place(map_id=second.id, name="Hai", name_key="hai"),
        )
        session.add_all([a, b])
        session.flush()
        ids = first.id, a.id, b.id
    with pytest.raises(IntegrityError), transaction(engine) as session:
        session.add(
            Route(
                map_id=ids[0],
                name="Wrong map",
                from_place_id=ids[1],
                to_place_id=ids[2],
                revision=1,
            )
        )


def test_place_casefold_retains_accents_and_revision_is_monotonic(engine):
    map_id = catalog.create_map(engine, "Map")["id"]
    a = catalog.create_place(engine, map_id, "CỬA VÀO")["id"]
    with pytest.raises(ApiError, match="VALIDATION_ERROR"):
        catalog.create_place(engine, map_id, "cửa vào")
    b = catalog.create_place(engine, map_id, "cua vao")["id"]
    request = RouteCreate(name="Route", map_id=map_id, from_place_id=a, to_place_id=b)
    assert [catalog.create_route(engine, request)["revision"] for _ in range(3)] == [1, 2, 3]


def test_embedding_portable_bytes_and_invalid_stored_data_rejected():
    vector = (1.0,) + (0.0,) * 767
    encoded = catalog.pack_vector(vector)
    assert len(encoded) == 3072 and encoded[:4] == b"\x00\x00\x80?"
    assert catalog.unpack_vector(encoded) == vector
    for value in (b"", b"\x00" * 3072):
        with pytest.raises(ValueError):
            catalog.unpack_vector(value)


def test_reference_constraint_and_transaction_roll_back_checkpoint(engine):
    map_id = catalog.create_map(engine, "Map")["id"]
    places = [catalog.create_place(engine, map_id, name)["id"] for name in ("A", "B")]
    route_id = catalog.create_route(
        engine,
        RouteCreate(name="Route", map_id=map_id, from_place_id=places[0], to_place_id=places[1]),
    )["id"]
    with pytest.raises(IntegrityError), transaction(engine) as session:
        point = Checkpoint(route_id=route_id, seq=0, depart_action="straight", landmark="A")
        session.add(point)
        session.flush()
        session.add(
            ReferenceImage(
                checkpoint_id=point.id,
                jpeg_bytes=b"jpg",
                width=64,
                height=64,
                pixel_sha256="a" * 64,
                source_group="ref",
                embedding=b"bad",
                encoder_fingerprint="b" * 64,
            )
        )
    with transaction(engine) as session:
        assert session.scalars(select(Checkpoint)).all() == []
        assert session.scalars(select(ReferenceImage)).all() == []
