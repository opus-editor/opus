/**
 * The row the {@link TabBarPill}s sit in, laying them out itself: a plain
 * Gtk.Box can only reorder its children, so a tab changing place would
 * jump straight to its new slot. Here every pill has an `x` of its own
 * that slides to where the order puts it — libadwaita's AdwTabBox does
 * the same, with the same 250ms.
 */
namespace EditorView.EditorPane {
  public class TabBarRow : Gtk.Widget {
    private const int SPACING = 4;
    private const uint SLIDE_DURATION_MS = 250;

    private class Slot : Object {
      /** Where the pill is drawn right now. */
      public double x = 0;
      /** Where the order puts it. */
      public double target_x = 0;
      /** A pill's first layout puts it straight at its slot — nothing to slide from. */
      public bool placed = false;
      public Adw.TimedAnimation? slide = null;
    }

    private HashTable<Gtk.Widget, Slot> slots = new HashTable<Gtk.Widget, Slot> (direct_hash, direct_equal);

    construct {
      add_css_class ("tab-row");
    }

    public void append (Gtk.Widget child) {
      slots[child] = new Slot ();
      child.insert_before (this, null);
    }

    public void remove (Gtk.Widget child) {
      var slot = slots[child];
      if (slot != null) {
        slot.slide?.pause ();
        slots.remove (child);
      }
      child.unparent ();
    }

    /** `child` goes right after `sibling` (first, for null); the others slide out of its way. */
    public void reorder_child_after (Gtk.Widget child, Gtk.Widget? sibling) {
      child.insert_after (this, sibling);
      queue_allocate ();
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
      minimum = 0;
      natural = 0;
      minimum_baseline = -1;
      natural_baseline = -1;
      var count = 0;
      for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
        if (!child.should_layout ()) {
          continue;
        }
        int child_minimum, child_natural;
        child.measure (orientation, -1, out child_minimum, out child_natural, null, null);
        if (orientation == Gtk.Orientation.HORIZONTAL) {
          minimum += child_minimum;
          natural += child_natural;
          count++;
        } else {
          minimum = int.max (minimum, child_minimum);
          natural = int.max (natural, child_natural);
        }
      }
      if (orientation == Gtk.Orientation.HORIZONTAL && count > 1) {
        minimum += SPACING * (count - 1);
        natural += SPACING * (count - 1);
      }
    }

    public override void size_allocate (int width, int height, int baseline) {
      double x = 0;
      for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
        if (!child.should_layout ()) {
          continue;
        }
        int child_minimum, child_natural;
        child.measure (Gtk.Orientation.HORIZONTAL, -1, out child_minimum, out child_natural, null, null);
        var slot = slots[child];
        slot.target_x = x;
        x += child_natural + SPACING;
        settle (slot);
        child.allocate (child_natural, height, -1, new Gsk.Transform ().translate (Graphene.Point () { x = (float) slot.x, y = 0 }));
      }
    }

    /** Puts `slot` where its order says: straight there on its first layout, sliding otherwise — and never restarting a slide already headed there. */
    private void settle (Slot slot) {
      if (!slot.placed) {
        slot.x = slot.target_x;
        slot.placed = true;
        return;
      }
      if (slot.x == slot.target_x) {
        return;
      }
      if (slot.slide != null && slot.slide.state == Adw.AnimationState.PLAYING && slot.slide.value_to == slot.target_x) {
        return;
      }
      slot.slide?.pause ();
      var target = new Adw.CallbackAnimationTarget ((value) => {
        slot.x = value;
        queue_allocate ();
      });
      slot.slide = new Adw.TimedAnimation (this, slot.x, slot.target_x, SLIDE_DURATION_MS, target);
      slot.slide.play ();
    }

    public override void dispose () {
      foreach (var slot in slots.get_values ()) {
        slot.slide?.pause ();
      }
      slots.remove_all ();
      Gtk.Widget? child;
      while ((child = get_first_child ()) != null) {
        child.unparent ();
      }
      base.dispose ();
    }
  }
}
