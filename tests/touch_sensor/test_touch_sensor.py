import json
import time
from typing import Tuple
from unittest.mock import MagicMock, mock_open, patch

import pytest

from config.pipe_config import TAP_DATA_PIPE
from config.touch_sensor_config import TIMESTAMP_FORMAT
from src.touch_sensor.touch_sensor import TapStatus, TouchSensor


DEBOUNCE_TIME = 0.001  # Time in seconds


@pytest.fixture
def mock_fifo() -> MagicMock:
    """Creates a mock file object for simulating FIFO file operations.

    Returns:
        A MagicMock instance simulating a file object.
    """
    return mock_open()


@pytest.fixture
def touch_sensor(mock_fifo: MagicMock) -> TouchSensor:
    """Fixture to provide a TouchSensor instance for testing.

    The TouchSensor is initialized with a mock FIFO path and a predefined
    debounce time.

    Args:
        mock_fifo: The mock FIFO file object.

    Returns:
        An instance of TouchSensor initialized for testing.
    """
    return TouchSensor(
        debounce_time=DEBOUNCE_TIME, 
        tap_data_pipe=TAP_DATA_PIPE
    )


class TestDebounceBehavior:
    """Test suite for testing the debounce behavior of the TouchSensor."""

    @pytest.fixture(params=[
        (0.0, False), 
        (DEBOUNCE_TIME - 0.0001, False), 
        (DEBOUNCE_TIME, True), 
        (DEBOUNCE_TIME + 0.0001, True)
    ])
    def test_values(self, request) -> Tuple[float, bool]:
        """Parameterized fixture providing test values for debounce tests.
        
        Args:
            request: The fixture request object provided by pytest.
            
        Returns:
            A tuple containing a wait time and the expected result of a tap
            after that wait time.
        """
        return request.param

    def test_basic_debounce_behavior(
        self, 
        touch_sensor: TouchSensor, 
        test_values: Tuple[float, bool]
    ) -> None:
        """Tests that a tap is registered or ignored according to the debounce logic.
        
        Args:
            touch_sensor: The TouchSensor fixture for testing.
            test_values: A tuple of wait time and expected boolean result.
        """
        wait_time, expected = test_values
        touch_sensor.tap()
        time.sleep(wait_time)
        assert touch_sensor.tap() == expected

    def test_reset_debounce_time_behavior(
        self, 
        touch_sensor: TouchSensor, 
        test_values: Tuple[float, bool]
    ) -> None:
        """Tests the reset of the debounce timer when a tap is registered.
                
        Args:
            touch_sensor: The TouchSensor fixture for testing.
            test_values: A tuple of wait time and expected boolean result.
        """
        wait_time, expected = test_values
        touch_sensor.tap()  # Debounce timer starts
        touch_sensor.tap()  # Debounce timer is reset
        time.sleep(wait_time)
        assert touch_sensor.tap() == expected


class TestSendingRequestToScreenPipe:
    """Test suite for testing the communication of the TouchSensor with the screen pipe."""

    @pytest.mark.parametrize('tap_status', [TapStatus.GOOD, TapStatus.BAD])
    def test_writing_to_tap_data_pipe(
        self, 
        tap_status: str, 
        touch_sensor: TouchSensor
    ) -> None:
        """Tests correctly writing to the tap data pipe.

        This test verifies that the TouchSensor correctly formats and sends tap data 
        based on the given type (success or failure) to the tap data pipe.

        Args:
            type: The type of tap event to send, can be 'success' or 'failure'.
            touch_sensor: The TouchSensor instance used for testing.
        """
        sample_data = {
            'status': tap_status, 
            'data': {
                'timestamp': time.strftime(TIMESTAMP_FORMAT, time.gmtime(0))
            }
        }
        
        with patch('src.touch_sensor.touch_sensor.open', mock_fifo):
            touch_sensor.pipe_tap_data(tap_status, time.gmtime(0))
            mock_fifo().write.assert_called_once_with(json.dumps(sample_data))