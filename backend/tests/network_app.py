"""External-process integration adapter; deliberately outside the installable server package."""

from navcore.app import create_app
from navcore.settings import Settings
from tests.integration.test_catalog_api import FixtureEncoder

app = create_app(Settings.from_env(), vision=FixtureEncoder())
