from django.conf import settings


# Optional plugins live in the source tree but are not installed by default.
# Avoid importing their models during Django's project-wide test discovery;
# Django imports every Python package below the test root, including this
# package, even when the plugin is disabled.
if any(item.startswith('sp_external_status_providers') for item in settings.INSTALLED_APPS):
    from .models import *
    from .bulk import *
    from .filtersets import *
