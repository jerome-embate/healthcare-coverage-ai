"""Smoke test: the package installs and imports through the src/ layout."""

from coverage_agent import main


def test_main_prints_greeting(capsys):
    main()
    assert capsys.readouterr().out == "Hello from coverage-agent!\n"
