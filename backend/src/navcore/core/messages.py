from navcore.core.types import InstructionCode as Code
from navcore.core.types import Priority

MESSAGES = {
    Code.CONTINUE_STRAIGHT: ("Tiếp tục theo hành lang.", Priority.GUIDANCE),
    Code.TURN_LEFT: ("Đến chỗ rẽ. Rẽ trái.", Priority.GUIDANCE),
    Code.TURN_RIGHT: ("Đến chỗ rẽ. Rẽ phải.", Priority.GUIDANCE),
    Code.ARRIVED: ("Đã đến điểm đích của tuyến.", Priority.GUIDANCE),
    Code.HOLD_POSITION: ("Chưa xác định được vị trí. Hướng dẫn đang tạm dừng.", Priority.WARNING),
    Code.OBJECT_AHEAD: (
        "Hình ảnh cho thấy vật thể phía trước. Hãy kiểm tra đường đi.",
        Priority.WARNING,
    ),
    Code.EMERGENCY_STOP: ("Có vật cản rất gần. Hãy dừng lại nếu có thể.", Priority.EMERGENCY),
    Code.OBSTACLE_NEAR: ("Có vật cản gần phía trước. Hướng dẫn đang tạm dừng.", Priority.WARNING),
    Code.OBSTACLE_NOTICE: ("Có vật thể đang ở gần hướng đi.", Priority.INFO),
    Code.DEPTH_UNAVAILABLE: (
        "Chưa nhận được khoảng cách đáng tin cậy. Hướng dẫn đang tạm dừng.",
        Priority.WARNING,
    ),
    Code.WAIT_FOR_FRESH_FRAME: ("Đang chờ hình ảnh mới để hướng dẫn.", Priority.INFO),
}


def message(code: Code) -> tuple[str, Priority]:
    return MESSAGES[code]
