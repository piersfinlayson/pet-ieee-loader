# Changelog

## 0.1.1

Create ROM version, which can be installed at $9000 or $A000.  In this case the first cassette buffer (located at $27A) is used for RAM.

When installed as the $9000 ROM, the program can be activated with `SYS 36864`.  The device ID is changed with `POKE 634,8` (to set to 8 - the default remains device 30).

## 0.1.0

First release, with Run, Execute and Load functionality working.