from django.http import JsonResponse
from django.views.decorators.http import require_GET


@require_GET
def healthz(request):
    """Lightweight liveness endpoint for Docker and ALB health checks."""
    return JsonResponse({'status': 'ok'})
