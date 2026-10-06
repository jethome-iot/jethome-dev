# Run by verify.sh under `pytest -n auto`, the way a consumer parallelises its
# suite. The assertion is about where the test runs, not what it computes: a
# plugin that failed to load would not get this far (`-n` and `worker_id` are
# both its own), and one that loaded but ran the suite in-process would answer
# "master" here. worker_id is read from the session xdist set up rather than from
# PYTEST_XDIST_WORKER, which an in-process run could inherit from its caller.


def test_runs_in_an_xdist_worker(worker_id: str) -> None:
    assert worker_id.startswith("gw"), worker_id
