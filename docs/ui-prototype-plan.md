# NekoPic interactive desktop UI prototype

Goal: provide a Chinese desktop editor prototype for visual review, as authorized in the conversation. No native application or project-file format is included.

Current scope (user clarification): UI interaction review only. Keep existing exploratory code, but defer further image processing implementation and correctness acceptance until the UI is approved. Functional checklist items below remain pending; they are not release claims.

Design: graphite workspace, warm peach accent, persistent desktop menus and tool rail, central photo canvas, contextual inspector, bottom status and zoom controls. Editing is local in the browser.

Files: `index.html` for semantic layout and dialogs, `styles.css` for visual design, `app.js` for editing and interaction, `assets/demo.jpg` for an offline sample, and `README.md` for launch instructions and browser limitations.

- [x] Build the desktop shell, responsive canvas workspace and local sample image.
- [ ] Implement image import, adjustment preview, drawing, editable text and shapes, selection, undo/redo, rotation, comparison and zoom.
- [ ] Implement Save / Save As with PNG, JPEG and WebP, native file picker where supported and download fallback. No project persistence.
- [ ] Verify in a real browser: initial appearance, adjustment pixels, shape/text manipulation, undo, rotation, file formats, image import and dialog interactions. Inspect screenshots at desktop sizes.
- [ ] Launch a local server, open the prototype and provide its address.

Scope notes: masks, perspective editing, arbitrary crop and professional colour management are outside this visual prototype. Any visible unsupported operation must be clearly identified, not presented as working.

## Added requirements and fixed rules

- Rotate/flip transforms both photo and objects. Crop translates the coordinate system and clips objects. Resize scales photo, positions and object dimensions together. Canvas size is a separate anchored expansion operation.
- A stroke, slider drag and text editing session each produce one undo entry.
- Saving flattens the file only, retains the editable in-memory objects, and clears dirty state at that exact revision. Later edits become dirty. Reopening the output loads a flattened image.
- Limits: 32 megapixels, 8192 pixels per edge, 80 history entries / approximately 128 MiB of serialized history, 4096 samples per stroke. Browser recovery uses IndexedDB, is best effort, and is not an engineering project format.
- Include eyedropper with loupe, filter presets and intensity, rectangle mosaic/blur, multiline outlined text with CJK fallback, base shapes, Shift constraints, zoom/pan, clipboard, dark/light theme, recent file access where browser handles permit, shortcut help and recovery.
- Input is decoded using browser EXIF orientation and colour conversion into sRGB canvas. Export uses sRGB pixels, default strips metadata; full EXIF/ICC preservation is explicitly not offered in this browser prototype. JPEG background is configurable. Native colour correctness requires separate verification.
- CLI integration, full print pipeline, bilingual UI and professional pen/brush tuning are desktop follow-ups, not simulated as implemented.
