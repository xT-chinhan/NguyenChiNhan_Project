from navcore.cli._benchmark_metrics import Metrics, performance_decision


def test_four_session_capacity_does_not_accept_stale_output_or_unmeasured_device():
    stats = Metrics(0, 30, 300, 4)
    for session in "abcd":
        request = stats.request(session, 1, 40)
        stats.sent(request, 40000)
        stats.result(request, 40.1, {"timing": {key: 1 for key in stats.timing}})
    stats.rtt_ms.append(10)

    def decision():
        return performance_decision(
            stats.summary(),
            sessions=4,
            warmup=30,
            duration=300,
            completed=True,
            attested=True,
            real_models=True,
            standard_frames=True,
            standard_route=True,
        )["status"]

    assert decision() == "MEASURED_CAPACITY"
    stats.counts["stale_results_received"] = 1
    assert decision() == "FAIL_FRESHNESS"
    stats.counts["stale_results_received"] = 0
    stats.per_session.pop("d")
    assert decision() == "FAIL_FRESHNESS"
