#!/usr/bin/env python3
"""Exercise failure and recovery through the real CLI, using disposable state."""
import json
import os

from _common import detail, ensure_build, isolated, run


def main():
    cli, _ = ensure_build()
    checks = []
    with isolated() as (root, env):
        # status consults MacKit's profile; isolate that read as well as app data.
        env = {**env, "XDG_CONFIG_HOME": str(root / "xdg")}
        support = root / "support"
        config = support / "config.json"
        status = support / "status.json"

        def invoke(*args, expected=0):
            return run([cli, *args], env=env, expected=expected)

        def listing():
            return json.loads(invoke("list", "--json").stdout)

        def no_write(*args, expected=2):
            before = config.read_bytes()
            result = invoke(*args, expected=expected)
            assert config.read_bytes() == before, f"{' '.join(args)} changed rejected config"
            return result

        defaults = listing()
        assert defaults["right"]["enabled"] is True
        assert defaults["right"]["hold"] is True
        assert defaults["left"]["doubleTap"] is True
        assert not config.exists(), "reading defaults unexpectedly created config"
        checks.append("Missing configuration loads defaults without writing a file")

        invoke("disable", "right")
        assert listing()["right"]["enabled"] is False
        valid = config.read_bytes()
        checks.append("First explicit update creates a readable configuration")

        for label, damaged in [
            ("invalid JSON", b'{"right": invalid-json\n'),
            ("invalid field type", b'{"right":{"enabled":"not-a-bool"}}\n'),
        ]:
            config.write_bytes(damaged)
            result = no_write("list", "--json")
            assert "cannot read" in result.stderr
            result = no_write("enable", "right")
            assert "cannot read" in result.stderr
            # Diagnostic status must still work while the config is damaged.
            diagnostic = json.loads(no_write("status", "--json", expected=3).stdout)
            assert diagnostic["running"] is False
            assert diagnostic["intercepting"] is False
            checks.append(f"{label}: read/write fail, original bytes survive, status remains usable")

            config.write_bytes(valid)
            assert listing()["right"]["enabled"] is False
            invoke("enable", "right")
            assert listing()["right"]["enabled"] is True
            invoke("disable", "right")
            assert listing()["right"]["enabled"] is False
            checks.append(f"{label}: restored valid configuration resumes CLI reads and writes")

        for args, expected in [
            (("hold", "sometimes"), 2),
            (("enable", "middle"), 2),
            (("list", "--side", "middle"), 2),
            (("unset", "1"), 2),
            (("unset", "z"), 1),
            (("import", "--bogus"), 2),
            (("hold", "on", "--bogus"), 2),
            (("enable", "right", "--side", "left"), 2),
            (("move", "a", "b"), 1),
        ]:
            no_write(*args, expected=expected)
        assert listing()["right"]["enabled"] is False
        checks.append("Invalid arguments and missing bindings leave configuration byte-identical")

        # Int32.max is outside macOS's PID allocation range. Confirm it is absent
        # before using it as a stale status fixture rather than assuming liveness.
        absent_pid = 2_147_483_647
        try:
            os.kill(absent_pid, 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError("stale PID fixture unexpectedly exists")
        stale = {
            "pid": absent_pid,
            "accessibilityTrusted": True,
            "tapEnabled": True,
            "version": "fixture-stale",
            "updated": "2000-01-01T00:00:00Z",
        }
        # A live process that is not Initials (this runner) must not read as the app either.
        foreign = {**stale, "pid": os.getpid(), "version": "fixture-foreign"}
        for label, payload in [
            ("missing", None),
            ("malformed", b"not JSON\n"),
            ("stale PID", json.dumps(stale).encode()),
            ("foreign live PID", json.dumps(foreign).encode()),
        ]:
            if payload is None:
                status.unlink(missing_ok=True)
            else:
                status.write_bytes(payload)
            result = json.loads(no_write("status", "--json", expected=3).stdout)
            assert result["running"] is False and result["ok"] is False
            no_write("pause", expected=3)
            assert result["accessibilityTrusted"] is False
            assert result["intercepting"] is False
            assert result["config"] == str(config)
            if payload is not None:
                assert status.read_bytes() == payload, "status query changed diagnostic state"
            checks.append(f"{label} status reports not-running and never claims interception")

        status.unlink()
        invoke("enable", "right")
        assert listing()["right"]["enabled"] is True
        checks.append("Final update succeeds after status failure scenarios")

    detail(
        "recovery",
        f"PASS: {len(checks)} isolated CLI failure/recovery checks",
        checks=checks,
        boundary="Real CLI and disposable config/status files; no normal GUI launch, "
        "EventTap restart, OS permission recovery, synthetic input, or user state mutation.",
    )


if __name__ == "__main__":
    main()
