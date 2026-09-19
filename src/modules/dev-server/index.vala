/**
 * A D-Bus control surface for whichever Opus windows are currently open —
 * exists purely so the assistant working on this codebase can drive the
 * real, already-running app from the terminal (`gdbus call …`) instead of
 * reconstructing a throwaway harness for every check. Debug builds only
 * (see main.vala's own `#if DEBUG` around where this gets constructed and
 * started) — never registered, so never reachable, in a release build.
 *
 * Piggybacks on the application's own existing D-Bus connection/bus name
 * (`io.github.nowaos.Opus`, already owned by Adw.Application/GApplication
 * itself) rather than owning a second name of its own — this interface is
 * exported as one more object alongside GApplication's own, at
 * `<app's own object path>/Dev`.
 *
 * Deliberately thin: every method here just calls straight through to an
 * EditorController's own already-public methods (a couple of which —
 * open_paths(), active_document_path, set_active_content(), and making
 * save_path() itself public — exist only because this needed to reach
 * them from outside, not because the real UI needed them). Nothing here
 * holds business logic of its own, and nothing outside this file/
 * DEBUG-gated call site knows this class exists — deleting it wouldn't
 * change anything else in the app.
 */
namespace Opus.Dev {
    [DBus (name = "io.github.nowaos.Opus.Dev")]
    public interface DevInterface : Object {
        /** Opens a brand-new "Untitled-N" tab, focused immediately — same as the sidebar's "New File". */
        public abstract void new_file () throws DBusError, IOError;

        /** Opens `path` as a permanent tab — same as a double-click. Already-open just activates it, same as clicking its tab. */
        public abstract void open_tab (string path) throws DBusError, IOError;

        /** Closes `path`'s tab outright, no unsaved-changes prompt (same as discard_tab()) — a dev tool has no dialog to answer. */
        public abstract void close_tab (string path) throws DBusError, IOError;

        /**
         * Saves `path` specifically, regardless of which tab is active.
         * Not `async`: valac's own GDBus codegen for an async interface
         * method's dispatch stub always emits an `_error:` label nothing
         * in that function ever jumps to (real async errors surface in
         * the ready callback instead) — an unconditional, unfixable
         * warning for *any* async D-Bus method, not particular to this
         * one (confirmed directly: a bare synchronous method generates no
         * such label at all). EditorController.save_path()'s own
         * synchronous case (an already-named file, the common one) has no
         * yield point in it at all, so it still runs to completion before
         * this returns either way; only the rare untitled-document case
         * (needing a save-as dialog) becomes genuinely fire-and-forget.
         */
        public abstract void save_tab (string path) throws DBusError, IOError;

        /** Replaces the active tab's entire buffer content — simulates a real edit (dirty tracking and all), just not through a real keypress. */
        public abstract void set_active_text (string text) throws DBusError, IOError;

        /** Replaces the active tab's cursor set — `anchors[i]`/`positions[i]` pair up into one cursor each (collapsed when equal). Lets a system test seed a multi-cursor starting state directly, without typing/clicking it into place first. */
        public abstract void set_active_cursors (int[] anchors, int[] positions) throws DBusError, IOError;

        /** The active tab's current buffer content, or "" if none — the reverse of set_active_text(). */
        public abstract string get_active_text () throws DBusError, IOError;

        /** The active tab's current cursor set, or two empty arrays if none — the reverse of set_active_cursors(). */
        public abstract void get_active_cursors (out int[] anchors, out int[] positions) throws DBusError, IOError;

        /**
         * Simulates one keystroke on the active tab exactly as a real one
         * would be reported (same keyval/modifier shape as Gdk, e.g.
         * `Gdk.ModifierType.CONTROL_MASK` for Ctrl) — driving the real
         * CursorController dispatch, not a shortcut around it. Returns
         * whether anything claimed the key. The system-test DSL's `type`/
         * `type_cmd` both resolve to this: `type` looks up each
         * character's own keyval and calls this once per character;
         * `type_cmd` resolves a named command (e.g. "undo") to its
         * keyval + modifiers the same way a real Ctrl+Z would arrive.
         */
        public abstract bool key_press (uint keyval, uint modifiers) throws DBusError, IOError;

        /**
         * Fires GtkTextView's own native "select-all" (Ctrl+A) action on
         * the active tab directly — the system-test DSL's `select_all`.
         * Not routed through key_press(): unlike an ordinary keystroke,
         * "select-all" is a GTK keybinding-action signal, reachable
         * (and faithfully exercised) without needing a real GTK event
         * at all — see EditorView.simulate_select_all()'s own doc
         * comment for why.
         */
        public abstract void select_all () throws DBusError, IOError;

        /** Every currently open tab's path, across whichever window this call happens to land on (see current_editor_controller()'s own comment). */
        public abstract string[] list_open_tabs () throws DBusError, IOError;

        /** The active tab's path, or "" if none is. */
        public abstract string get_active_tab () throws DBusError, IOError;

        public abstract bool is_dirty (string path) throws DBusError, IOError;
    }

    public class DevServer : Object, DevInterface {
        // One entry per open window's own EditorController — main.vala
        // adds/removes as windows open/close (see build_session()'s own
        // #if DEBUG block). Every method here operates on whichever one
        // was added *last*: good enough for a one-window dev loop, which
        // is the only scenario this was actually built for — resolving
        // "which window" properly would need a whole addressing scheme
        // for a case that doesn't come up in practice.
        private GenericArray<EditorController> editor_controllers = new GenericArray<EditorController> ();
        private uint registration_id = 0;

        public void add_session (EditorController editor_controller) {
            editor_controllers.add (editor_controller);
        }

        public void remove_session (EditorController editor_controller) {
            uint index;
            if (editor_controllers.find (editor_controller, out index)) {
                editor_controllers.remove_index (index);
            }
        }

        /** Exports this interface on `connection` at `object_path` — called once the application's own D-Bus connection actually exists (main.vala's own Adw.Application.startup handler), not before. */
        public void start (DBusConnection connection, string object_path) {
            if (registration_id != 0) {
                return;
            }

            try {
                registration_id = connection.register_object (object_path, (DevInterface) this);
            } catch (IOError e) {
                warning ("failed to start the dev D-Bus server: %s", e.message);
            }
        }

        private EditorController current_editor_controller () throws DBusError {
            if (editor_controllers.length == 0) {
                throw new DBusError.FAILED ("No Opus window is open");
            }
            return editor_controllers[editor_controllers.length - 1];
        }

        public void new_file () throws DBusError, IOError {
            current_editor_controller ().new_untitled ();
        }

        public void open_tab (string path) throws DBusError, IOError {
            try {
                current_editor_controller ().open (path, true);
            } catch (Error e) {
                throw new IOError.FAILED (e.message);
            }
        }

        public void close_tab (string path) throws DBusError, IOError {
            current_editor_controller ().discard_tab (path);
        }

        public void save_tab (string path) throws DBusError, IOError {
            current_editor_controller ().save_path.begin (path);
        }

        public void set_active_text (string text) throws DBusError, IOError {
            current_editor_controller ().set_active_content (text);
        }

        public void set_active_cursors (int[] anchors, int[] positions) throws DBusError, IOError {
            current_editor_controller ().set_active_cursors (anchors, positions);
        }

        public string get_active_text () throws DBusError, IOError {
            return current_editor_controller ().active_content;
        }

        public void get_active_cursors (out int[] anchors, out int[] positions) throws DBusError, IOError {
            current_editor_controller ().get_active_cursors (out anchors, out positions);
        }

        public bool key_press (uint keyval, uint modifiers) throws DBusError, IOError {
            return current_editor_controller ().simulate_key_press (keyval, modifiers);
        }

        public void select_all () throws DBusError, IOError {
            current_editor_controller ().simulate_select_all ();
        }

        public string[] list_open_tabs () throws DBusError, IOError {
            return current_editor_controller ().open_paths ();
        }

        public string get_active_tab () throws DBusError, IOError {
            return current_editor_controller ().active_document_path ?? "";
        }

        public bool is_dirty (string path) throws DBusError, IOError {
            return current_editor_controller ().is_dirty (path);
        }
    }
}
