import json
import os
import time
from typing import Dict, Any, NamedTuple, Generator
import mmap
import logging
import logging.config

from PIL import Image
import numpy as np
import portalocker

from config.screen_config import *
from src.utils.paths import (DISPLAY_FRAME_BUFFER_PATH,
                             DISPLAY_FRAME_BUFFER_LOCK_PATH, PROJECT_DIR)
from src.utils.utils import SelfReleasingLock

caller_name = os.path.basename(__import__('__main__').__file__).split('.')[0]
file_name = os.path.basename(__file__).split('.')[0]
logging.config.fileConfig(f"{PROJECT_DIR}/config/logging.conf", disable_existing_loggers=False)
logger = logging.getLogger(f"{caller_name}.{file_name}")


class DisplayAttributes(NamedTuple):
    """Represents display-related attributes.

    Attributes:
        display_fb_path (str): Path to the display framebuffer.
        display_height (int): Height of the display in pixels.
        display_width (int): Width of the display in pixels.
        display_frame_rate (int): Frame rate for display updates.
    """
    display_fb_path: str = DISPLAY_FRAME_BUFFER_PATH
    display_fb_lock_path: str = DISPLAY_FRAME_BUFFER_LOCK_PATH
    display_height: str = DISPLAY_HEIGHT
    display_width: str = DISPLAY_WIDTH
    display_frame_rate: str = DISPLAY_FRAME_RATE


class DashboardAttributes(NamedTuple):
    """Contains attributes specific to the dashboard's appearance.

    Attributes:
        dashboard_font_family (str): Font family for the dashboard text.
        dashboard_font_size (int): Font size for the dashboard text.
        dashboard_font_color (str): Color of the dashboard text.
        dashboard_bg_color (str): Background color of the dashboard.
    """
    dashboard_font_family: str = DASHBOARD_FONT_FAMILY
    dashboard_font_size: int = DASHBOARD_FONT_SIZE
    dashboard_font_color: str = DASHBOARD_FONT_COLOR
    dashboard_bg_color: str = DASHBOARD_BG_COLOR


class EventAttributes(NamedTuple):
    """Defines attributes for various event backgrounds.

    Attributes:
        popup_error_bg_color (str): Background color for error popups.
        popup_warning_bg_color (str): Background color for warning popups.
        tap_event_bg_color (str): Background color for tap event messages.
        order_set_bg_color (str): Background color for order set messages.
        employee_set_bg_color (str): Background color for employee set messages.
    """
    popup_error_bg_color: str = POPUP_ERROR_BG_COLOR
    popup_warning_bg_color: str = POPUP_WARNING_BG_COLOR
    tap_event_bg_color: str = TAP_EVENT_BG_COLOR
    order_set_bg_color: str = ORDER_SET_BG_COLOR
    order_same_bg_color: str = ORDER_SAME_BG_COLOR
    no_order_bg_color: str = NO_ORDER_BG_COLOR
    employee_set_bg_color: str = EMPLOYEE_SET_BG_COLOR
    employee_same_bg_color: str = EMPLOYEE_SAME_BG_COLOR
    no_employee_bg_color: str = NO_EMPLOYEE_BG_COLOR


class MessageAttributes(NamedTuple):
    """Represents attributes related to the messaging in popups and events.

    Attributes:
        popup_font_family (str): Font family for popup messages.
        popup_font_size (int): Font size for popup messages.
        popup_font_color (str): Color of the popup message text.
        popup_error_message (str): Default message for error popups.
        popup_warning_message (str): Default message for warning popups.
        tap_event_message (str): Default message for tap event notifications.
        order_set_message (str): Default message for order set notifications.
        employee_set_message (str): Default message for employee set notifications.
    """
    popup_font_family: str = POPUP_FONT_FAMILY
    popup_font_size: int = POPUP_FONT_SIZE
    popup_font_color: str = POPUP_FONT_COLOR
    popup_error_message: str = POPUP_ERROR_MESSAGE
    popup_warning_message: str = POPUP_WARNING_MESSAGE
    tap_event_message: str = TAP_EVENT_MESSAGE
    order_set_message: str = ORDER_SET_MESSAGE
    order_same_message: str = ORDER_SAME_MESSAGE
    no_order_message: str = NO_ORDER_MESSAGE
    employee_set_message: str = EMPLOYEE_SET_MESSAGE
    employee_same_message: str = EMPLOYEE_SAME_MESSAGE
    no_employee_message: str = NO_EMPLOYEE_MESSAGE


class PopupAttributes(NamedTuple):
    """Encapsulates attributes specifically for popup configuration.

    Attributes:
        event_attributes (NamedTuple): Attributes related to event backgrounds.
        message_attributes (NamedTuple): Attributes pertaining to messaging in popups.
        popup_duration (int): Duration to display popups (in seconds).
    """
    event_attributes: NamedTuple = EventAttributes()
    message_attributes: NamedTuple = MessageAttributes()
    popup_duration: int = POPUP_DURATION


def is_at_least_next_day(from_timestamp: float, to_timestamp: float) -> bool:
    """Check if the 'to_timestamp' is at least the next day compared to 'from_timestamp'.

    Args:
        from_timestamp (float): The starting Unix timestamp.
        to_timestamp (float): The ending Unix timestamp.

    Returns:
        bool: True if 'to_timestamp' is at least the next day from 'from_timestamp', False otherwise.
    """
    day_in_seconds = 86400
    # Get the start of the day for both timestamps
    from_day_start = from_timestamp - (from_timestamp % day_in_seconds)
    to_day_start = to_timestamp - (to_timestamp % day_in_seconds)

    # Check if to_timestamp is at least the next day from from_timestamp
    return to_day_start > from_day_start

def read_pipe(path_to_pipe: str) -> Generator[Dict[str, Any], None, None]:
    """Read and parse JSON data from a named pipe.

    Args:
        path_to_pipe (str): Path to the named pipe.

    Returns:
        Dict[str, Any]: A dictionary containing the parsed data from the pipe.

    Raises:
        FileNotFoundError: If the named pipe does not exist.
    """
    # TODO: Consider using user space os.open command instead of built-in open
    while True:
        try:
            # Open the pipe in a blocking mode
            pipe_fd = os.open(path_to_pipe, os.O_RDONLY)
            with os.fdopen(pipe_fd, 'r') as pipein:
                while True:
                    raw_data = pipein.readline()
                    if raw_data:
                        yield json.loads(raw_data)
                    else:
                        # If raw_data is empty, this means the pipe has been closed by the writer
                        logger.info("Pipe closed by the writer. Re-opening the pipe.")
                        break  # Exit the inner loop to close the file descriptor and reopen the pipe
        except FileNotFoundError:
            logger.error(f"Could not find {path_to_pipe} while attempting to open the pipe.")
            raise
        except OSError as e:
            logger.error(f"An error occurred while handling the pipe {path_to_pipe}: {str(e)}")
            raise
        except Exception as e:
            # Handle other possible exceptions and decide whether to continue or stop
            logger.error(f"An unexpected error occurred: {str(e)}")
            raise

        # Optionally add a slight delay before trying to reopen the pipe to prevent tight loop under error conditions
        time.sleep(1)


def get_image_center(image: Image) -> tuple[int, int]:
    """Get the center coordinates of an image.

    Returns:
        tuple[int, int]: The center coordinates (x, y) of the image, or (-1, -1) if no image is set.
    """
    if image:
        width, height = image.size
        center_x, center_y = width // 2, height // 2
        return (center_x, center_y)
    return (-1, -1)


def image_to_raw_rgb565(image: Image) -> np.ndarray:
    """Convert a PIL image to raw RGB565 format.

    Args:
        image (Image): The PIL image to convert.

    Returns:
        np.ndarray: A numpy array containing the image data in RGB565 format.
    """
    # Split into R, G, B channels
    r, g, b = image.split()
    # Convert each channel to an appropriate numpy array
    r = np.array(r, dtype=np.uint16)
    g = np.array(g, dtype=np.uint16)
    b = np.array(b, dtype=np.uint16)
    # Right shift to fit into 565 format
    r >>= 3  # Keep top 5 bits
    g >>= 2  # Keep top 6 bits
    b >>= 3  # Keep top 5 bits
    # Combine into RGB 565 format
    rgb565 = (r << 11) | (g << 5) | b
    # Convert the 2D array to a 1D array (raw data)
    raw_rgb565 = rgb565.ravel()
    return raw_rgb565


def write_image_to_fb(image: Image, path_to_fb: str, path_to_fb_lock: str) -> None:
    """Write a PIL image to a framebuffer device in RGB565 format.

    Args:
        image (Image): The PIL image to write.
        path_to_fb (str): Path to the framebuffer device.
        path_to_fb_lock (str): Path to the framebuffer lock file.
    
    Raises:
        FileNotFoundError: If the framebuffer device path does not exist.
        IOError: If there is an error writing to the framebuffer.
    """
    try:
        raw_data = image_to_raw_rgb565(image)
        raw_bytes = raw_data.tobytes()

        width, height = image.size
        screensize = width * height * 2

        if len(raw_bytes) != screensize:
            raise ValueError('Size mismatch: Data size does not match buffer size')

        fbfd = os.open(path_to_fb, os.O_RDWR)
        fbp = mmap.mmap(fbfd, screensize, flags=mmap.MAP_SHARED, prot=mmap.PROT_WRITE)
        fbp[:] = raw_bytes
        fbp.flush()
        os.close(fbfd)
    except FileNotFoundError:
        logger.error(f"Could not find {path_to_fb} while writing to framebuffer")
        raise FileNotFoundError  # TODO: Determine error message format
    except IOError as e:
        logger.error(f"An error occurred while writing to framebuffer: {e}")
        raise IOError  # TODO: Determine error message format
