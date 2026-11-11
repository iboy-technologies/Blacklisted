"""Use a webcam and hand landmarks to control the Windows mouse cursor.

The camera must be visible to the operating system as a normal webcam. A phone
can be used when it is configured as a webcam through the phone's companion
application.
"""

import argparse
import os
import time
import tkinter as tk
import urllib.request
from tkinter import messagebox, ttk

import cv2
import mediapipe as mp
import pyautogui
from mediapipe.tasks import python
from mediapipe.tasks.python import vision


MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
    "hand_landmarker/float16/1/hand_landmarker.task"
)
MODEL_PATH = os.path.join(os.path.dirname(__file__), ".camera_mouse", "hand_landmarker.task")
HAND_CONNECTIONS = (
    (0, 1), (1, 2), (2, 3), (3, 4),
    (0, 5), (5, 6), (6, 7), (7, 8),
    (5, 9), (9, 10), (10, 11), (11, 12),
    (9, 13), (13, 14), (14, 15), (15, 16),
    (13, 17), (17, 18), (18, 19), (19, 20),
    (0, 17),
)
PINCH_THRESHOLD = 0.055
OTHER_PINCH_THRESHOLD = 0.075
DRAG_HOLD_SECONDS = 0.28


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Control the mouse with an index finger.")
    parser.add_argument("--camera", type=int, default=0, help="Camera device index (default: 0).")
    parser.add_argument(
        "--smoothing",
        type=float,
        default=0.28,
        help="Cursor smoothing from 0.05 to 1.0 (default: 0.28).",
    )
    parser.add_argument(
        "--margin",
        type=float,
        default=0.08,
        help="Dead margin around the camera image from 0.0 to 0.3 (default: 0.08).",
    )
    return parser.parse_args()


def clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(value, upper))


def remap(value: float, margin: float) -> float:
    return clamp((value - margin) / (1.0 - (margin * 2.0)), 0.0, 1.0)


def ensure_model() -> None:
    if os.path.isfile(MODEL_PATH):
        return
    os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)
    print("Downloading the hand-tracking model...")
    try:
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
    except Exception as error:
        if os.path.isfile(MODEL_PATH):
            os.remove(MODEL_PATH)
        raise RuntimeError(
            "Could not download the hand-tracking model. Check your internet connection."
        ) from error


def draw_hand(frame, landmarks) -> None:
    height, width = frame.shape[:2]
    points = [(int(point.x * width), int(point.y * height)) for point in landmarks]
    for start, end in HAND_CONNECTIONS:
        cv2.line(frame, points[start], points[end], (80, 230, 210), 2)
    for point in points:
        cv2.circle(frame, point, 4, (255, 255, 255), -1)


def choose_camera_source(default_camera: int) -> tuple[object, str] | None:
    selection = {"source": None, "label": ""}
    root = tk.Tk()
    root.title("Blacklisted Camera Mouse Setup")
    root.resizable(False, False)
    root.protocol("WM_DELETE_WINDOW", root.destroy)

    choice = tk.StringVar(value="pc")
    pc_index = tk.StringVar(value=str(default_camera))
    phone_url = tk.StringVar(value="http://192.168.1.100:8080/video")
    consent = tk.BooleanVar(value=False)

    content = ttk.Frame(root, padding=18)
    content.grid()
    ttk.Label(
        content,
        text="Choose the camera that will control your mouse.",
        font=("Segoe UI", 11, "bold"),
    ).grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 12))
    ttk.Radiobutton(
        content,
        text="PC camera",
        variable=choice,
        value="pc",
    ).grid(row=1, column=0, sticky="w")
    ttk.Label(content, text="Device index:").grid(row=1, column=1, padx=(18, 4))
    ttk.Spinbox(content, from_=0, to=9, width=5, textvariable=pc_index).grid(row=1, column=2)
    ttk.Radiobutton(
        content,
        text="Phone camera over LAN",
        variable=choice,
        value="phone",
    ).grid(row=2, column=0, sticky="w", pady=(10, 0))
    ttk.Label(content, text="Stream URL:").grid(row=3, column=0, sticky="w", pady=(4, 0))
    phone_entry = ttk.Entry(content, width=44, textvariable=phone_url)
    phone_entry.grid(row=3, column=1, columnspan=2, sticky="ew", pady=(4, 0))
    ttk.Label(
        content,
        text="Example: http://PHONE_IP:8080/video or rtsp://PHONE_IP:8554/live",
        foreground="#666666",
    ).grid(row=4, column=0, columnspan=3, sticky="w", pady=(4, 12))
    ttk.Checkbutton(
        content,
        text="I consent to using the selected camera for mouse control.",
        variable=consent,
    ).grid(row=5, column=0, columnspan=3, sticky="w")

    def submit() -> None:
        if not consent.get():
            messagebox.showwarning(
                "Consent required",
                "Please confirm consent before enabling camera mouse control.",
                parent=root,
            )
            return
        if choice.get() == "pc":
            try:
                selection["source"] = int(pc_index.get())
            except ValueError:
                messagebox.showerror("Invalid camera", "Device index must be a number.", parent=root)
                return
            selection["label"] = f"PC camera {selection['source']}"
        else:
            url = phone_url.get().strip()
            if not url.startswith(("http://", "https://", "rtsp://")):
                messagebox.showerror(
                    "Invalid stream URL",
                    "Use an http://, https://, or rtsp:// phone stream URL.",
                    parent=root,
                )
                return
            selection["source"] = url
            selection["label"] = "Phone camera"
        root.destroy()

    buttons = ttk.Frame(content)
    buttons.grid(row=6, column=0, columnspan=3, sticky="e", pady=(16, 0))
    ttk.Button(buttons, text="Cancel", command=root.destroy).grid(row=0, column=0, padx=(0, 8))
    ttk.Button(buttons, text="Use selected camera", command=submit).grid(row=0, column=1)
    root.mainloop()
    if selection["source"] is None:
        return None
    return selection["source"], selection["label"]


def main() -> None:
    args = parse_args()
    smoothing = clamp(args.smoothing, 0.05, 1.0)
    margin = clamp(args.margin, 0.0, 0.3)

    camera_source = choose_camera_source(args.camera)
    if camera_source is None:
        return
    source, source_label = camera_source
    ensure_model()
    camera = (
        cv2.VideoCapture(source, cv2.CAP_DSHOW)
        if isinstance(source, int)
        else cv2.VideoCapture(source)
    )
    if not camera.isOpened():
        raise RuntimeError(
            f"Could not open {source_label}. Check the camera settings and LAN stream URL."
        )

    screen_width, screen_height = pyautogui.size()
    pyautogui.PAUSE = 0.0
    pyautogui.FAILSAFE = True
    hand_tracker = vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=vision.RunningMode.VIDEO,
        num_hands=1,
        min_detection_confidence=0.7,
        min_hand_presence_confidence=0.7,
        min_tracking_confidence=0.6,
    ))

    cursor_x = screen_width / 2.0
    cursor_y = screen_height / 2.0
    active_gesture = None
    gesture_started_at = 0.0
    dragging = False
    paused = False
    window_name = "Blacklisted Camera Mouse"

    try:
        while True:
            success, frame = camera.read()
            if not success:
                raise RuntimeError("The camera stopped returning frames.")

            frame = cv2.flip(frame, 1)
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
            timestamp_ms = int(time.monotonic() * 1000)
            result = hand_tracker.detect_for_video(image, timestamp_ms)
            hand = result.hand_landmarks[0] if result.hand_landmarks else None
            gesture = None

            if hand:
                index_tip = hand[8]
                middle_tip = hand[12]
                thumb_tip = hand[4]
                target_x = remap(index_tip.x, margin) * screen_width
                target_y = remap(index_tip.y, margin) * screen_height
                cursor_x += (target_x - cursor_x) * smoothing
                cursor_y += (target_y - cursor_y) * smoothing

                index_pinch_distance = (
                    (index_tip.x - thumb_tip.x) ** 2 + (index_tip.y - thumb_tip.y) ** 2
                ) ** 0.5
                middle_pinch_distance = (
                    (middle_tip.x - thumb_tip.x) ** 2 + (middle_tip.y - thumb_tip.y) ** 2
                ) ** 0.5
                if (
                    index_pinch_distance < PINCH_THRESHOLD
                    and middle_pinch_distance > OTHER_PINCH_THRESHOLD
                ):
                    gesture = "left"
                elif (
                    middle_pinch_distance < PINCH_THRESHOLD
                    and index_pinch_distance > OTHER_PINCH_THRESHOLD
                ):
                    gesture = "right"

                now = time.monotonic()
                if not paused:
                    pyautogui.moveTo(int(cursor_x), int(cursor_y), _pause=False)
                    if gesture != active_gesture:
                        previous_gesture = active_gesture
                        if previous_gesture == "left":
                            if dragging:
                                pyautogui.mouseUp(button="left")
                                dragging = False
                            elif gesture is None:
                                pyautogui.click()
                        elif previous_gesture == "right":
                            pyautogui.click(button="right")
                        if gesture is not None:
                            gesture_started_at = now
                        active_gesture = gesture
                    if (
                        active_gesture == "left"
                        and not dragging
                        and now - gesture_started_at >= DRAG_HOLD_SECONDS
                    ):
                        pyautogui.mouseDown(button="left")
                        dragging = True
                    if active_gesture == "right" and gesture != "right":
                        pyautogui.click(button="right")
                        active_gesture = None

                draw_hand(frame, hand)

            if not hand and not paused and active_gesture is not None:
                if active_gesture == "left":
                    if dragging:
                        pyautogui.mouseUp(button="left")
                        dragging = False
                    else:
                        pyautogui.click()
                elif active_gesture == "right":
                    pyautogui.click(button="right")
                active_gesture = None
            status = "PAUSED (P to resume)" if paused else "TRACKING"
            cv2.putText(
                frame,
                f"{source_label}  |  {status}  |  index pinch: click/drag  |  middle pinch: right click  |  P: pause  |  Q/Esc: quit",
                (16, 32),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.65,
                (80, 230, 210),
                2,
                cv2.LINE_AA,
            )
            cv2.imshow(window_name, frame)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27):
                break
            if key == ord("p"):
                paused = not paused
    finally:
        if dragging:
            pyautogui.mouseUp(button="left")
        camera.release()
        hand_tracker.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
