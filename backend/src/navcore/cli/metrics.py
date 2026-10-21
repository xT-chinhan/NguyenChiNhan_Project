"""Independent event/window and object-IoU scoring; no navigation core calls."""

import math

from navcore.cli.dataset import ClipLabel


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = (len(ordered) - 1) * q
    lo = int(index)
    return ordered[lo] + (ordered[min(lo + 1, len(ordered) - 1)] - ordered[lo]) * (index - lo)


def valid_presentation(event: dict) -> bool:
    try:
        now, capture, received, deadline = (
            event[key]
            for key in (
                "presented_monotonic_ms",
                "capture_monotonic_ms",
                "received_monotonic_ms",
                "valid_until_monotonic_ms",
            )
        )
        return (
            all(
                type(v) in {int, float} and math.isfinite(v)
                for v in (now, capture, received, deadline)
            )
            and 0 <= now - capture < 1000
            and received <= now < deadline <= capture + 1000
        )
    except KeyError:
        return False


def navigation_metrics(clip: ClipLabel, events: list[dict]) -> dict:
    frames = {e["seq"]: e for e in events if e.get("type") == "frame_result"}
    presented = [
        e for e in events if e.get("type") == "instruction_presented" and valid_presentation(e)
    ]
    labels = {label.seq: label for label in clip.checkpoints}
    matched, ordered, false_turns, early_turns, early_arrivals, forbidden = (
        set(),
        [],
        0,
        0,
        0,
        0,
    )
    for event in presented:
        code, pts = event.get("code"), event.get("video_pts_ms")
        frame = frames.get(event.get("frame_seq"), {})
        seq = frame.get("last_confirmed_seq")
        label = labels.get(seq)
        correct = (
            label is not None
            and label.expected_code == code
            and label.visible_start_ms <= pts <= label.visible_end_ms
        )
        if correct:
            matched.add(seq)
            if not ordered or ordered[-1] != seq:
                ordered.append(seq)
        if code in {"TURN_LEFT", "TURN_RIGHT"} and not correct:
            false_turns += 1
            if label is not None and label.expected_code == code and pts < label.visible_start_ms:
                early_turns += 1
        if code == "ARRIVED" and not correct:
            early_arrivals += 1
        for interval in clip.forbidden_intervals:
            if interval.start_ms <= pts <= interval.end_ms and code in interval.codes:
                forbidden += 1
    last, out_of_route, skipped, wrong_window = -1, 0, 0, 0
    for event in events:
        if event.get("type") != "frame_result" or not event.get("accepted_fresh"):
            continue
        seq = event.get("last_confirmed_seq", -1)
        if type(seq) is not int or seq <= last:
            continue
        if not clip.expected_completion and seq not in clip.allowed_confirmed_seqs:
            out_of_route += 1
        if clip.expected_completion:
            label, pts = labels.get(seq), event.get("video_pts_ms")
            if (
                label is None
                or type(pts) not in {int, float}
                or not label.visible_start_ms <= pts <= label.visible_end_ms
            ):
                wrong_window += 1
        if seq > last + 1:
            skipped += 1
        last = seq
    missed = sum(
        label.expected_code in {"TURN_LEFT", "TURN_RIGHT"} and label.seq not in matched
        for label in clip.checkpoints
    )
    completed = (
        clip.expected_completion
        and ordered == sorted(labels)
        and len(matched) == len(labels)
        and bool(labels)
        and wrong_window == 0
    )
    return {
        "false_turns": false_turns,
        "early_turns": early_turns,
        "missed_turns": missed,
        "early_arrivals": early_arrivals,
        "out_of_route_progress": out_of_route,
        "forbidden_instructions": forbidden,
        "skipped_checkpoints": skipped,
        "wrong_window_progress": wrong_window,
        "completed": completed,
        "matched_checkpoint_seqs": sorted(matched),
    }


def iou(a, b) -> float:
    if (
        not isinstance(a, (list, tuple))
        or not isinstance(b, (list, tuple))
        or len(a) != 4
        or len(b) != 4
    ):
        return 0.0
    if not all(type(v) in {int, float} and math.isfinite(v) for v in (*a, *b)):
        return 0.0
    intersection = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(
        0, min(a[3], b[3]) - max(a[1], b[1])
    )
    union = (
        max(0, a[2] - a[0]) * max(0, a[3] - a[1])
        + max(0, b[2] - b[0]) * max(0, b[3] - b[1])
        - intersection
    )
    return intersection / union if union else 0.0


def perception_metrics(clip: ClipLabel, events: list[dict]) -> dict:
    frames = {
        e["video_pts_ms"]: e
        for e in events
        if e.get("type") == "frame_result" and e.get("accepted_fresh")
    }
    tp, fp, fn, observed, missing, object_frames, clear_frames = 0, 0, 0, 0, 0, 0, 0
    for label in clip.perception_frames:
        frame = frames.get(label.pts_ms)
        if frame is None:
            missing += 1
            continue
        observed += 1
        object_frames += bool(label.objects)
        clear_frames += not label.objects
        detections = [
            d
            for d in frame.get("obstacles", [])
            if d.get("class_name") in {"person", "chair"}
            and type(d.get("confidence")) in {int, float}
            and math.isfinite(d["confidence"])
            and d["confidence"] >= 0.38
        ]
        pairs = sorted(
            (
                (iou(d.get("bbox"), obj.bbox), di, oi)
                for di, d in enumerate(detections)
                for oi, obj in enumerate(label.objects)
                if d["class_name"] == obj.class_name
            ),
            reverse=True,
        )
        used_d, used_o = set(), set()
        for overlap, di, oi in pairs:
            if overlap >= 0.5 and di not in used_d and oi not in used_o:
                used_d.add(di)
                used_o.add(oi)
        tp += len(used_d)
        fp += len(detections) - len(used_d)
        fn += len(label.objects) - len(used_o)
    return {
        "true_positives": tp,
        "false_positives": fp,
        "false_negatives": fn,
        "labelled_frames_observed": observed,
        "labelled_frames_missing": missing,
        "object_frames_observed": object_frames,
        "clear_frames_observed": clear_frames,
    }
