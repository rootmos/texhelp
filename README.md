# TeX Live helper

[![Tests](https://github.com/rootmos/texhelp/actions/workflows/tests.yaml/badge.svg)](https://github.com/rootmos/texhelp/actions/workflows/tests.yaml)

```sh
wget -O- https://raw.githubusercontent.com/rootmos/texhelp/refs/heads/master/texhelp | sh -s -- -i
```
or clone the repository and
```sh
./texhelp -i
```
installs an isolated [TeX Live](https://tug.org/texlive/) system in `.texhelp` (or `$TEXHELP_DESTDIR`),
which can be activated à la [Python's venv](https://docs.python.org/3/library/venv.html):
```sh
. .texhelp/activate
```
which brings [`tlmgr`](https://man.archlinux.org/man/tlmgr.1),
[`pdflatex`](https://man.archlinux.org/man/pdflatex.1)
and friends to the party.
