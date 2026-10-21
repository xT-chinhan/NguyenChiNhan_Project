# Public video: Zaragoza Ada Byron

Đã tải và chạy thử video hành lang góc nhìn thứ nhất từ Universidad de Zaragoza. Đây là pipeline smoke với model thật, không phải bộ nghiệm thu dẫn đường độc lập.

Nguồn chính thức: [RGB-D indoor dataset, Scenario1 Ada Byron](https://webdiis.unizar.es/~glopez/dataset.html). Dataset nghiên cứu: [First-person view RGB-D dataset, Zenodo](https://zenodo.org/records/6322990). Tác giả công bố dữ liệu cho nghiên cứu hỗ trợ người khiếm thị; video web là bản RGB nén, không chứa depth/calibration của rosbag.

## File để xem và chạy lại

- MP4 cục bộ: [ada-indoor-rgb.mp4](../../backend/output/public-video/zaragoza-ada/ada-indoor-rgb.mp4).
- Nguồn FLV giữ nguyên: [Ada.flv](../../backend/output/public-video/zaragoza-ada/Ada.flv).
- Sample manifest: [frames.jsonl](../../backend/output/public-video/zaragoza-ada/frames/frames.jsonl).
- [Report JSON](public-video-zaragoza.json), [server receipt](server-public-video.json).

ffprobe đo182.753s,572×428,30fps; FLV24,235,020 byte. Prepare-video tạo914 ảnh upright5fps. Bản MP4 chỉ để xem thuận tiện, bỏ audio; replay lấy samples từ FLV gốc. Không tải rosbag nhiềuGB. Không thay đổi bytes nguồn, không publish/redistribute media.

SHA256 FLV: `8ac1563c9e979d74cf0e937c9eef493c7af6277d7759ec0a86847ee9b51187e8`.
SHA256 trace cuối: `87c303267bed733e0d1af71b0afbd9ff5a4bc650ab5e4b811eb0edb17d22abd4`.

## Lần chạy cuối

| Số đo | Kết quả |
|---|---|
| Capture requests / frames sent | 490 / 490 |
| Frame results | 489 |
| Stale instructions presented | 0 |
| Client request→receive p50/p95/p99 | 267 / 618 / 720 ms |
| HOLD_POSITION presentations trước/sau sửa | 500 / 33 |
| Khoảng nhắc lost ngắn nhất đo sau sửa | 5015ms |
| Checkpoint cuối xác nhận | 0 |
| Route/perception accuracy | Chưa đo |

Video chạy hết nguồn ở tốc độ1x; request cuối rơi đúng lúc kết thúc nên490 gửi/489 kết quả, không được coi một missing result đó là frame đã xử lý thành công. Có2 frame localizing,54 navigating và433 lost. Backend xác nhận điểm0 rồi mất định vị, tiếp tục giữ movement hold và yêu cầu resume để định vị lại. Không tự rẽ để đoán tuyến.

Lần đầu phát HOLD_POSITION500 lần. Bản sửa dùng cooldown5000ms trong staged state mỗi phiên; lần cuối33 lần, giữ hold trong mọi frame lost. Hai traces từ hai source snapshots khác nhau được giữ nguyên, không tái gắn hash cũ thành hash mới. Các regression tests kiểm cả cooldown, resume và stale mutation.

## Phạm vi bằng chứng

Smoke bundle có4 checkpoint/3 refs, lấy từ chính clip này và dùng action placeholder. Nó chỉ tạo workload hợp lệ để kiểm import/vision/API/WS/TTL; không có ground truth tuyến. Vì thế G3/G4 vẫn BLOCKED_DATA, G5 NOT_RUN. Không báo navigation accuracy hoặc detector precision/recall, không suy ra camera RGB đo được khoảng cách/TTC.

Số đo độ trễ thuộc một replay182.753s trên mạng loopback CPU, có các kiểm tra dev chạy nền trong một phần thời gian. Nó không thay30s warmup+300s1/4-session benchmark. Stdout simulation chưa kiểm audio/TTS. Chưa có RGB-D hardware, app hoặc thử với người dùng thật.

Source cuối: `e3f00d6f727378bfd8cbade748418f78813d917190a78042af900d73e877786c`.
Image: `sha256:747d8abf71978823a700167785cc3010a0d99012d9aa42b5ac4e1c250e2d58fa`.
Models/policy/lock/source và trace được buộc vào [local operator receipt](server-public-video.json), đối chiếu byte source trong [container receipt](container-final.json). Đây là bằng chứng cục bộ, không phải remote cryptographic attestation.
