"""Verify that the running Django application can enqueue and complete an RQ job."""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

project_root = Path(__file__).resolve().parents[1] / "statuspage"
sys.path.insert(0, str(project_root))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "statuspage.settings")
os.environ.setdefault("STATUS_PAGE_CONFIGURATION", "statuspage.configuration")

import django

django.setup()

from django_rq import get_queue
from rq.job import JobStatus


def main() -> None:
    queue = get_queue("default")
    job = queue.enqueue(sum, [2, 3])

    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        job.refresh()
        if job.get_status() == JobStatus.FINISHED:
            if job.result != 5:
                raise RuntimeError(f"RQ job returned {job.result!r}; expected 5.")
            print(f"RQ smoke test passed: job {job.id} returned {job.result}.")
            return
        if job.is_failed:
            raise RuntimeError(f"RQ job {job.id} failed: {job.exc_info}")
        time.sleep(1)

    raise TimeoutError(f"RQ job {job.id} did not finish within 30 seconds.")


if __name__ == "__main__":
    main()
