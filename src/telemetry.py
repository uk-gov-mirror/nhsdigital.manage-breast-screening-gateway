import logging
import os

logger = logging.getLogger(__name__)


def configure_telemetry(service_name: str | None = None) -> None:
    """Configure OpenTelemetry with Azure Monitor.

    If APPLICATIONINSIGHTS_CONNECTION_STRING is not set, this is a no-op,
    so local development works without any Azure configuration.

    Args:
        service_name: Identifies this service in Application Insights.
    """
    if not os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
        return

    if service_name:
        os.environ.setdefault("OTEL_SERVICE_NAME", service_name)

    from azure.monitor.opentelemetry import configure_azure_monitor

    configure_azure_monitor()
    logger.info("Azure Monitor telemetry configured")
