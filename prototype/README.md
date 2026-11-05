# H5 prototype (reference only)

`h5/` contains the original browser prototype used as the visual and interaction
reference for NekoPic. It is not the product and is not part of the native build
or packaging.

```sh
cd prototype/h5
python3 -m http.server 8765 --bind 127.0.0.1
# open http://127.0.0.1:8765
```

`h5/assets` is a symlink to the repository-level `assets/` directory so the
prototype and the native app share the same demo photo without duplicating it.
On a platform where the symlink is not preserved, copy `assets/demo.jpg` into
`prototype/h5/assets/` manually.

Parity notes and differences live in
[`docs/h5-parity.md`](../docs/h5-parity.md) and
[`docs/h5-ui-audit.md`](../docs/h5-ui-audit.md). Do not add product features to
the prototype; implement them in `native/`.
