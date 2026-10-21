"""Initial catalog/device schema, frozen PostgreSQL DDL. No runtime model imports."""

from alembic import op

revision = "0001_catalog_devices"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
CREATE TABLE devices (
        id UUID NOT NULL,
        name VARCHAR(80) NOT NULL,
        token_sha256 VARCHAR(64) NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        revoked_at TIMESTAMP WITH TIME ZONE,
        PRIMARY KEY (id),
        UNIQUE (token_sha256)
)
""")
    op.execute("""
CREATE TABLE maps (
        id UUID NOT NULL,
        name VARCHAR(120) NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        PRIMARY KEY (id),
        CONSTRAINT map_name_nonblank CHECK (length(trim(name)) > 0)
)
""")
    op.execute("""
CREATE TABLE places (
        id UUID NOT NULL,
        map_id UUID NOT NULL,
        name VARCHAR(120) NOT NULL,
        name_key TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        PRIMARY KEY (id),
        CONSTRAINT place_map_name_key UNIQUE (map_id, name_key),
        CONSTRAINT place_id_map UNIQUE (id, map_id),
        CONSTRAINT place_name_nonblank CHECK (length(trim(name)) > 0),
        FOREIGN KEY(map_id) REFERENCES maps (id) ON DELETE RESTRICT
)
""")
    op.execute("""
CREATE TABLE routes (
        id UUID NOT NULL,
        map_id UUID NOT NULL,
        name VARCHAR(120) NOT NULL,
        from_place_id UUID NOT NULL,
        to_place_id UUID NOT NULL,
        revision INTEGER NOT NULL,
        status VARCHAR(16) DEFAULT 'draft' NOT NULL,
        encoder_fingerprint VARCHAR(64),
        route_fingerprint VARCHAR(64),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        published_at TIMESTAMP WITH TIME ZONE,
        PRIMARY KEY (id),
        CONSTRAINT route_from_same_map FOREIGN KEY(from_place_id, map_id) REFERENCES
places (id, map_id) ON DELETE RESTRICT,
        CONSTRAINT route_to_same_map FOREIGN KEY(to_place_id, map_id) REFERENCES places
(id, map_id) ON DELETE RESTRICT,
        CONSTRAINT route_directed_revision UNIQUE (map_id, from_place_id, to_place_id,
revision),
        CONSTRAINT route_distinct_endpoints CHECK (from_place_id <> to_place_id),
        CONSTRAINT route_revision_positive CHECK (revision >= 1),
        CONSTRAINT route_status CHECK (status IN ('draft','published')),
        CONSTRAINT route_published_bound CHECK (status <> 'published' OR
(encoder_fingerprint IS NOT NULL AND route_fingerprint IS NOT NULL AND published_at IS
NOT NULL)),
        CONSTRAINT route_name_nonblank CHECK (length(trim(name)) > 0),
        FOREIGN KEY(map_id) REFERENCES maps (id) ON DELETE RESTRICT
)
""")
    op.execute("""
CREATE INDEX route_lookup ON routes (map_id, from_place_id, to_place_id, status,
revision)
""")
    op.execute("""
CREATE TABLE checkpoints (
        id UUID NOT NULL,
        route_id UUID NOT NULL,
        seq INTEGER NOT NULL,
        depart_action VARCHAR(16) NOT NULL,
        landmark VARCHAR(120) NOT NULL,
        heading_deg FLOAT,
        heading_accuracy_deg FLOAT,
        PRIMARY KEY (id),
        CONSTRAINT checkpoint_route_seq UNIQUE (route_id, seq),
        CONSTRAINT checkpoint_seq_nonnegative CHECK (seq >= 0),
        CONSTRAINT checkpoint_action CHECK (depart_action IN
('straight','left','right','arrive')),
        CONSTRAINT checkpoint_heading CHECK (heading_deg >= 0 AND heading_deg < 360),
        CONSTRAINT checkpoint_heading_accuracy CHECK (heading_accuracy_deg >= 0 AND
heading_accuracy_deg <= 180),
        CONSTRAINT checkpoint_heading_pair CHECK (heading_accuracy_deg IS NULL OR
heading_deg IS NOT NULL),
        FOREIGN KEY(route_id) REFERENCES routes (id) ON DELETE RESTRICT
)
""")
    op.execute("""
CREATE TABLE reference_images (
        id UUID NOT NULL,
        checkpoint_id UUID NOT NULL,
        jpeg_bytes BYTEA NOT NULL,
        width SMALLINT NOT NULL,
        height SMALLINT NOT NULL,
        pixel_sha256 VARCHAR(64) NOT NULL,
        source_group VARCHAR(80) NOT NULL,
        embedding BYTEA NOT NULL,
        encoder_fingerprint VARCHAR(64) NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        PRIMARY KEY (id),
        CONSTRAINT reference_checkpoint_pixel UNIQUE (checkpoint_id, pixel_sha256),
        CONSTRAINT reference_embedding_bytes CHECK (octet_length(embedding) = 3072),
        CONSTRAINT reference_dimensions CHECK (width BETWEEN 32 AND 1280 AND height
BETWEEN 32 AND 720),
        FOREIGN KEY(checkpoint_id) REFERENCES checkpoints (id) ON DELETE RESTRICT
)
""")


def downgrade():
    op.drop_table("reference_images")
    op.drop_table("checkpoints")
    op.drop_table("routes")
    op.drop_table("places")
    op.drop_table("maps")
    op.drop_table("devices")
