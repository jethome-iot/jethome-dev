# Run by verify.sh under `pytest -n auto`, the way a consumer parallelises its
# suite. The assertion is about where the test runs, not what it computes: xdist
# sets PYTEST_XDIST_WORKER in each worker process and nowhere else, so a plugin
# that failed to load would not get this far (`-n` is its option), and one that
# loaded but ran the suite in-process would fail here.
import os


def test_runs_in_an_xdist_worker() -> None:
    assert os.environ.get("PYTEST_XDIST_WORKER", "").startswith("gw")
