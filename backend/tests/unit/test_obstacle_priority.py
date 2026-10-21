import numpy as np

from navcore.core.depth import DepthFrame
from navcore.core.obstacles import ObstacleAssessor
from navcore.core.types import InstructionCode, Mode, SensorProfile, TrackState


def test_ttc_emergency_overrides_simultaneous_near_distance_warning():
    assessor = ObstacleAssessor()
    sensor = SensorProfile(Mode.RGBD, 0.001, "calibration")
    track = TrackState(1, 0, "person", (0, 0, 20, 20), 0.9, 3, 0)
    for capture, raw_range in ((0, 1100), (100, 900), (200, 600)):
        raw = np.full((100, 100), 2000, dtype=np.uint16)
        raw[:20, :20] = raw_range
        track.last_seen_ms = capture
        result = assessor.assess(
            [track],
            DepthFrame(raw, capture, True, "calibration"),
            sensor,
            capture,
            image_size=(100, 100),
            frame_seq=capture + 1,
        )
    assert track.ttc_s is not None and track.ttc_s < 2
    assert result.hold and result.code == InstructionCode.EMERGENCY_STOP
