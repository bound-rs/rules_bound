"""A first-party library with package data."""

from importlib.resources import files


def text() -> str:
    return files(__name__).joinpath("greeting.txt").read_text().strip()
