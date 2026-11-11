"""Use a webcam and hand landmarks to control the Windows mouse cursor.

The camera must be visible to the operating system as a normal webcam. A phone
can be used when it is configured as a webcam through the phone's companion
application.
"""

import argparse
import time

import cv2
import mediapipe as mp
import pyautogui


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


def main() -> None:
    args = parse_args()
    smoothing = clamp(args.smoothing, 0.05, 1.0)
    margin = clamp(args.margin, 0.0, 0.3)

    camera = cv2.VideoCapture(args.camera, cv2.CAP_DSHOW)
    if not camera.isOpened():
        raise RuntimeError(
            f"Could not open camera {args.camera}. Check the camera index and Windows permissions."
        )

    screen_width, screen_height = pyautogui.size()
    pyautogui.PAUSE = 0.0
    pyautogui.FAILSAFE = True
    hands_module = mp.solutions.hands
    drawing = mp.solutions.drawing_utils
    hand_tracker = hands_module.Hands(
        static_image_mode=False,
        max_num_hands=1,
        model_complexity=0,
        min_detection_confidence=0.7,
        min_tracking_confidence=0.6,
    )

    cursor_x = screen_width / 2.0
    cursor_y = screen_height / 2.0
    was_pinched = False
    last_click = 0.0
    paused = False
    window_name = "Blacklisted Camera Mouse"

    try:
        while True:
            success, frame = camera.read()
            if not success:
                raise RuntimeError("The camera stopped returning frames.")

            frame = cv2.flip(frame, 1)
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            result = hand_tracker.process(rgb_frame)
            hand = result.multi_hand_landmarks[0] if result.multi_hand_landmarks else None
            pinched = False

            if hand:
                index_tip = hand.landmark[hands_module.HandLandmark.INDEX_FINGER_TIP]
                thumb_tip = hand.landmark[hands_module.HandLandmark.THUMB_TIP]
                target_x = remap(index_tip.x, margin) * screen_width
                target_y = remap(index_tip.y, margin) * screen_height
                cursor_x += (target_x - cursor_x) * smoothing
                cursor_y += (target_y - cursor_y) * smoothing

                pinch_distance = ((index_tip.x - thumb_tip.x) ** 2 + (index_tip.y - thumb_tip.y) ** 2) ** 0.5
                pinched = pinch_distance < 0.055
                now = time.monotonic()
                if not paused:
                    pyautogui.moveTo(int(cursor_x), int(cursor_y), _pause=False)
                    if pinched and not was_pinched and now - last_click > 0.35:
                        pyautogui.click()
                        last_click = now

                drawing.draw_landmarks(frame, hand, hands_module.HAND_CONNECTIONS)

            was_pinched = pinched
            status = "PAUSED (P to resume)" if paused else "TRACKING"
            cv2.putText(
                frame,
                f"{status}  |  pinch: click  |  P: pause  |  Q/Esc: quit",
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
        camera.release()
        hand_tracker.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
