"""Catalog and device persistence. Session/frame state intentionally stays in RAM."""

import uuid
from datetime import datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    ForeignKeyConstraint,
    Index,
    Integer,
    LargeBinary,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Map(Base):
    __tablename__ = "maps"
    __table_args__ = (CheckConstraint("length(trim(name)) > 0", name="map_name_nonblank"),)
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Place(Base):
    __tablename__ = "places"
    __table_args__ = (
        UniqueConstraint("map_id", "name_key", name="place_map_name_key"),
        UniqueConstraint("id", "map_id", name="place_id_map"),
        CheckConstraint("length(trim(name)) > 0", name="place_name_nonblank"),
    )
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    map_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("maps.id", ondelete="RESTRICT"))
    name: Mapped[str] = mapped_column(String(120))
    name_key: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Route(Base):
    __tablename__ = "routes"
    __table_args__ = (
        ForeignKeyConstraint(
            ["from_place_id", "map_id"],
            ["places.id", "places.map_id"],
            ondelete="RESTRICT",
            name="route_from_same_map",
        ),
        ForeignKeyConstraint(
            ["to_place_id", "map_id"],
            ["places.id", "places.map_id"],
            ondelete="RESTRICT",
            name="route_to_same_map",
        ),
        UniqueConstraint(
            "map_id", "from_place_id", "to_place_id", "revision", name="route_directed_revision"
        ),
        CheckConstraint("from_place_id <> to_place_id", name="route_distinct_endpoints"),
        CheckConstraint("revision >= 1", name="route_revision_positive"),
        CheckConstraint("status IN ('draft','published')", name="route_status"),
        CheckConstraint(
            "status <> 'published' OR (encoder_fingerprint IS NOT NULL AND "
            "route_fingerprint IS NOT NULL AND published_at IS NOT NULL)",
            name="route_published_bound",
        ),
        CheckConstraint("length(trim(name)) > 0", name="route_name_nonblank"),
        Index("route_lookup", "map_id", "from_place_id", "to_place_id", "status", "revision"),
    )
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    map_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("maps.id", ondelete="RESTRICT"))
    name: Mapped[str] = mapped_column(String(120))
    from_place_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    to_place_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    revision: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(16), default="draft", server_default="draft")
    encoder_fingerprint: Mapped[str | None] = mapped_column(String(64))
    route_fingerprint: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Checkpoint(Base):
    __tablename__ = "checkpoints"
    __table_args__ = (
        UniqueConstraint("route_id", "seq", name="checkpoint_route_seq"),
        CheckConstraint("seq >= 0", name="checkpoint_seq_nonnegative"),
        CheckConstraint(
            "depart_action IN ('straight','left','right','arrive')", name="checkpoint_action"
        ),
        CheckConstraint("heading_deg >= 0 AND heading_deg < 360", name="checkpoint_heading"),
        CheckConstraint(
            "heading_accuracy_deg >= 0 AND heading_accuracy_deg <= 180",
            name="checkpoint_heading_accuracy",
        ),
        CheckConstraint(
            "heading_accuracy_deg IS NULL OR heading_deg IS NOT NULL",
            name="checkpoint_heading_pair",
        ),
    )
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    route_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("routes.id", ondelete="RESTRICT"))
    seq: Mapped[int] = mapped_column(Integer)
    depart_action: Mapped[str] = mapped_column(String(16))
    landmark: Mapped[str] = mapped_column(String(120))
    heading_deg: Mapped[float | None] = mapped_column(Float)
    heading_accuracy_deg: Mapped[float | None] = mapped_column(Float)


class ReferenceImage(Base):
    __tablename__ = "reference_images"
    __table_args__ = (
        UniqueConstraint("checkpoint_id", "pixel_sha256", name="reference_checkpoint_pixel"),
        CheckConstraint("octet_length(embedding) = 3072", name="reference_embedding_bytes"),
        CheckConstraint(
            "width BETWEEN 32 AND 1280 AND height BETWEEN 32 AND 720", name="reference_dimensions"
        ),
    )
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    checkpoint_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("checkpoints.id", ondelete="RESTRICT")
    )
    jpeg_bytes: Mapped[bytes] = mapped_column(LargeBinary)
    width: Mapped[int] = mapped_column(SmallInteger)
    height: Mapped[int] = mapped_column(SmallInteger)
    pixel_sha256: Mapped[str] = mapped_column(String(64))
    source_group: Mapped[str] = mapped_column(String(80))
    embedding: Mapped[bytes] = mapped_column(LargeBinary)
    encoder_fingerprint: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Device(Base):
    __tablename__ = "devices"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(80))
    token_sha256: Mapped[str] = mapped_column(String(64), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
