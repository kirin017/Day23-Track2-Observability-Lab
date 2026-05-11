# Day 23 Lab Reflection

**Học viên:** Nguyen Huu Huy 
**Ngày nộp:** 2026-05-11  


---

## 1. Cấu hình máy và kết quả setup

Kết quả chạy `python3 00-setup/verify-docker.py`:

```text
Docker:        OK  (28.0.4)
Compose v2:    OK  (2.34.0-desktop.1)
RAM available: 7.44 GB (OK)
Ports free:    OK
Report written: D:\Day23\Day23-Track2-Observability-Lab\00-setup\setup-report.json
```

Mình cũng đã commit file checkpoint vào `submission/setup-report.json`.

---

## 2. Track 02 — Dashboards & Alerts

### 6 panel chính (ảnh chụp)

Lưu tại `submission/screenshots/dashboard-overview.png`.

Dashboard overview hiển thị đúng 6 panel sau khi chạy load:
- Tốc độ request (RPS) theo trạng thái
- Độ trễ P50 / P95 / P99
- Tỉ lệ lỗi trong 5 phút gần nhất
- GPU Utilization
- Token Throughput (input/output mỗi giây)
- In-Flight Requests

Kết quả baseline load:
- 1054 request
- 0 lỗi ngoài mong đợi
- độ trễ trung bình 188 ms
- p50 160 ms
- p95 250 ms
- p99 290 ms
- throughput khoảng 17.63 req/s

### Panel burn-rate

Lưu tại `submission/screenshots/slo-burn-rate.png`.

Mình chạy kịch bản có lỗi kéo dài với `ERROR_RATE=0.2` trong 15 phút. Locust vẫn hiển thị `0` failure vì các phản hồi `503` trong bài test này được đánh dấu là expected success, nhưng phía Prometheus vẫn ghi nhận chúng là `status="error"`, nên Grafana hiển thị burn-rate khác 0 đúng như thiết kế.

Các giá trị burn-rate quan sát được:
- 5 phút: khoảng `39.96x`
- 30 phút: khoảng `22.95x`

### Alert fire + resolve

| Thời điểm | Sự kiện | Evidence |
|---|---|---|
| T0 | dừng `day23-app` | ảnh `submission/screenshots/alertmanager-firing.png` |
| T0+90s đến ~T0+115s | `ServiceDown` firing | ảnh `submission/screenshots/slack-firing.png` |
| T1 | khởi động lại app | container app phục hồi health check |
| T1+25s | alert resolved | ảnh `submission/screenshots/slack-resolved.png` |

### Một điều làm mình bất ngờ về Prometheus / Grafana

Điều làm mình bất ngờ nhất là dashboard-as-code có thể trông hoàn toàn đúng nhưng vẫn không có dữ liệu nếu datasource UID trong JSON không khớp với datasource thật của Grafana. Trong bài lab này, chỉ sau khi cố định UID của Prometheus datasource thì toàn bộ dashboard provision sẵn mới thực sự dùng được. Sự khác biệt nằm ở chỗ stack “đang chạy” không đồng nghĩa với stack “quan sát được”.

---

## 3. Track 03 — Tracing & Logs

### Một ảnh trace từ Jaeger

Lưu tại `submission/screenshots/jaeger-trace.png`.

Một trace mình tạo thủ công có:

```text
trace_id: 2e874a989b364445d5a255e4b97f2362
```

Trace này có thể tìm trong Jaeger với service `inference-api` và hiển thị đúng các span con:
- `embed-text`
- `vector-search`
- `generate-tokens`

### Một dòng log tương quan với trace

```json
{"model": "llama3-mock", "input_tokens": 4, "output_tokens": 54, "quality": 0.82, "duration_seconds": 0.1578, "event": "prediction served", "request_id": "6f0a0b7f-c7d1-4e8a-846d-0772e14a70ab", "level": "info", "timestamp": "2026-05-11T04:04:08.550609Z", "trace_id": "2e874a989b364445d5a255e4b97f2362", "span_id": "a07f77e9646d0e4c"}
```

Trace ID tương ứng:

```text
2e874a989b364445d5a255e4b97f2362
```

### Tính toán tail-sampling

Chính sách của collector là:
- giữ 100% trace lỗi
- giữ 100% trace có độ trễ trên 2 giây
- giữ 1% healthy trace

Trong bài test lỗi 15 phút, service xử lý khoảng `18,201` request, trong đó có khoảng `3,648` request lỗi. Suy ra số healthy request xấp xỉ:

```text
18,201 - 3,648 = 14,553
```

Số trace dự kiến được giữ lại:

```text
trace lỗi được giữ      = 3,648
trace healthy giữ 1%    = khoảng 146
trace healthy chậm >2s  = cộng thêm nếu có
tối thiểu giữ lại       ≈ 3,648 + 146 = 3,794
tỉ lệ giữ lại           ≈ 3,794 / 18,201 ≈ 20.8%
```

Trong kịch bản suy giảm này, phần lớn retention đến từ policy giữ trace lỗi, đây chính là điều mình mong muốn. Trace healthy được giảm mẫu mạnh để tiết kiệm chi phí, còn trace lỗi vẫn được giữ lại gần như đầy đủ để debug.

---

## 4. Track 04 — Drift Detection

### Điểm PSI

```json
{
  "prompt_length": {
    "psi": 3.461,
    "kl": 1.7982,
    "ks_stat": 0.702,
    "ks_pvalue": 0.0,
    "drift": "yes"
  },
  "embedding_norm": {
    "psi": 0.0187,
    "kl": 0.0324,
    "ks_stat": 0.052,
    "ks_pvalue": 0.133853,
    "drift": "no"
  },
  "response_length": {
    "psi": 0.0162,
    "kl": 0.0178,
    "ks_stat": 0.056,
    "ks_pvalue": 0.086899,
    "drift": "no"
  },
  "response_quality": {
    "psi": 8.8486,
    "kl": 13.5011,
    "ks_stat": 0.941,
    "ks_pvalue": 0.0,
    "drift": "yes"
  }
}
```

HTML report được tạo tại `04-drift-detection/reports/drift-report.html`.

### Feature nào nên dùng test nào?

Với `prompt_length`, mình chọn **PSI** trong production vì đây là scalar feature rất phù hợp với cách chia bucket, dễ giải thích với team vận hành và dễ đặt threshold cảnh báo. Độ dài prompt cũng là loại đặc trưng mà shift theo phân phối tổng quát thường quan trọng hơn từng điểm riêng lẻ.

Với `embedding_norm`, mình chọn **KS** vì đây là biến liên tục một chiều, phân phối tương đối mượt, và KS so sánh trực tiếp hai empirical CDF mà không cần giả định phân phối chuẩn. Nếu mình có toàn bộ vector embedding thay vì chỉ norm, mình sẽ cân nhắc **MMD**.

Với `response_length`, mình cũng chọn **KS** vì đây là một biến liên tục ở serving-time, phù hợp để phát hiện thay đổi hình dạng phân phối thay vì chỉ kiểm tra vài bucket cụ thể.

Với `response_quality`, mình chọn **KL** nếu quality score được xem như một phân phối xác suất hoặc phân phối gần-probability, vì KL rất nhạy với thay đổi hình dạng ở vùng chất lượng cao. Trong bài lab này, phân phối quality thay đổi mạnh và KL phản ánh rõ điều đó. Nếu cần metric dễ vận hành hơn cho dashboard, PSI vẫn có thể dùng như một chỉ báo phụ.

---

## 5. Track 05 — Cross-Day Integration

### Metric của ngày trước nào khó expose nhất? Vì sao?

Metric khó expose nhất theo mình là Day 20 `llama.cpp`. Script integration của repo cũng ghi rõ HTTP server của `llama.cpp` không tự có Prometheus metrics gốc, nên bài lab phải dùng sidecar hoặc stub để mô phỏng đúng shape metric của một model serving endpoint. Điều đó khiến phần khó không chỉ là scrape ở đâu, mà còn là định nghĩa metric nào mới thực sự hữu ích.

So với Day 19 Qdrant thì Day 20 khó hơn vì Qdrant vốn đã gần mô hình “có `/metrics` để scrape”. Với `llama.cpp`, khó khăn nằm ở ownership của instrumentation và schema metric, chứ không chỉ ở cấu hình Prometheus.

---

## 6. Thay đổi duy nhất tạo ra khác biệt lớn nhất

Thay đổi quan trọng nhất là giữ lại label `status` trên metric `inference_requests_total` để tách rõ traffic thành công và traffic lỗi ở ngay tầng metric. Nếu không có label này, service vẫn có thể expose volume request và latency, nhưng các rule burn-rate, panel error-rate và ngưỡng alert sẽ mất đi ý nghĩa thực tế. Sự khác biệt giữa “hệ thống đang bận” và “hệ thống đang đốt error budget” phụ thuộc trực tiếp vào việc có tách riêng failure signal hay không.

Điều này bám rất sát phần RED và SLO trong slide. RED yêu cầu đo rate, errors và duration, nhưng burn-rate alerting chỉ thật sự actionable khi error là một tín hiệu hạng nhất, có thể query theo nhiều cửa sổ thời gian khác nhau. Trong thực tế, quyết định thiết kế metric này quan trọng hơn bất kỳ chỉnh sửa giao diện dashboard nào, vì nó biến raw telemetry thành control signal cho alerting, debugging và ưu tiên xử lý sự cố.
