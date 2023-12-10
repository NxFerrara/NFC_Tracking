from enum import auto, Enum
from typing import NamedTuple

from utils import ftimestamp


class Tap(NamedTuple):
    """Stores information describing a tap event.

    Attributes:
        device_id: The ID of the device from which the tap was made.
        timestamp: The timestamp at which the tap was made.
        status: A TapStatus indicating the status of the tap.
    """
    device_id: str = ''
    timestamp: float = 0.0

    def __iter__(self):
        """Enable iteration over Tap attributes.

        This method allows the Tap instance to be converted to a dictionary.
        """
        for name, _ in self.__annotations__.items():
            yield name, getattr(self, name)
