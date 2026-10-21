"""Local Playwright smoke: Chromium fake camera, real backend, explicit device token file."""

import argparse
import json
import re
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument("--url", default="http://127.0.0.1:8095")
parser.add_argument("--device-env", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
values = dict(line.split("=", 1) for line in args.device_env.read_text().splitlines())
args.output.mkdir(parents=True, exist_ok=True)
with sync_playwright() as playwright:
    browser = playwright.chromium.launch(
        channel="chrome",
        headless=True,
        args=[
            "--use-fake-device-for-media-stream",
            "--use-fake-ui-for-media-stream",
        ],
    )
    context = browser.new_context(
        viewport={"width": 390, "height": 844}, permissions=["camera"], locale="vi-VN"
    )
    page = context.new_page()
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto(args.url + "/mobile")
    assert page.locator("h1").inner_text() == "Đi cùng hướng dẫn."
    page.locator("#token").fill(values["NAV_DEVICE_TOKEN"])
    page.locator("#connect").click()
    page.wait_for_selector("#catalog:not([hidden])")
    page.locator("#map").select_option(label="Public Zaragoza Ada - SMOKE ONLY")
    expect(page.locator("#from option")).to_have_count(2)
    page.locator("#from").select_option(label="Smoke start")
    page.locator("#to").select_option(label="Smoke end")
    page.locator("#find").click()
    page.locator("#route option").first.wait_for(state="attached")
    assert page.locator("#token").input_value() == ""
    page.locator("#audio").uncheck()
    page.locator("#start").click()
    expect(page.locator("#latency")).to_have_text(re.compile(r"ms$"), timeout=20000)
    assert page.locator("#video").evaluate(
        "(video) => video.videoWidth > 0 && video.srcObject.active"
    )
    page.screenshot(path=str(args.output / "mobile-camera.png"), full_page=True)
    page.locator("#pause").click()
    expect(page.locator("#state")).to_have_text("Đã tạm dừng")
    page.locator("#resume").click()
    expect(page.locator("#state")).to_have_text("Đang tìm vị trí")
    page.locator("#stop").click()
    expect(page.locator("#state")).to_have_text("Đã kết thúc")
    assert page.locator("#video").evaluate("(video) => video.srcObject === null")
    assert page.evaluate("Object.keys(localStorage).length") == 0
    assert page.evaluate("Object.keys(sessionStorage).length") == 0
    assert not errors, errors
    result = {
        "status": "PASS",
        "viewport": [390, 844],
        "camera": "Chromium synthetic camera",
        "backend": "real models and PostgreSQL, published smoke route",
        "checks": [
            "page loads",
            "token cleared from input, no browser storage",
            "maps/places/routes select",
            "browser WS message authentication",
            "fresh camera result through backend",
            "pause/resume/stop",
            "camera released on stop",
            "no browser runtime errors",
        ],
        "limitations": ["Synthetic browser camera; no physical phone or speech output verified"],
    }
    (args.output / "report.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    browser.close()
