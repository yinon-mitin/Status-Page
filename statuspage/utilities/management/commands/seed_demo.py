from django.core.management.base import BaseCommand

from components.choices import ComponentGroupCollapseChoices, ComponentStatusChoices
from components.models import Component, ComponentGroup


class Command(BaseCommand):
    help = 'Create or update safe demo data for the local presentation status page.'

    def handle(self, *args, **options):
        group_specs = [
            ('Core Platform', 'Public-facing services and application runtime.', 1),
            ('Data & Automation', 'Data stores and background processing.', 2),
        ]
        groups = {}
        for name, description, order in group_specs:
            group, _ = ComponentGroup.objects.update_or_create(
                name=name,
                defaults={
                    'description': description,
                    'visibility': True,
                    'order': order,
                    'collapse': ComponentGroupCollapseChoices.ALWAYS,
                },
            )
            groups[name] = group

        component_specs = [
            ('Web application', 'Core Platform', 'Main Status-Page web interface.', 1),
            ('Public API', 'Core Platform', 'Read-only status and integration API.', 2),
            ('PostgreSQL', 'Data & Automation', 'Primary application database.', 1),
            ('Redis and background jobs', 'Data & Automation', 'Queue, scheduler, and cache services.', 2),
        ]
        for name, group_name, description, order in component_specs:
            Component.objects.update_or_create(
                name=name,
                defaults={
                    'description': description,
                    'component_group': groups[group_name],
                    'visibility': True,
                    'status': ComponentStatusChoices.OPERATIONAL,
                    'show_historic_incidents': True,
                    'order': order,
                },
            )

        self.stdout.write(self.style.SUCCESS('Demo status page data is ready.'))
