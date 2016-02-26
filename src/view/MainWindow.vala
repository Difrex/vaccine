[GtkTemplate (ui = "/org/vaccine/app/main-window.ui")]
public class Vaccine.MainWindow : Gtk.ApplicationWindow {
    [GtkChild] private Gtk.HeaderBar headerbar;
    [GtkChild] private Gtk.SearchEntry searchentry;

    [GtkChild] private Gtk.Button choose_board_button;
    [GtkChild] private Gtk.ToggleButton show_search_bar_button;
    [GtkChild] private Gtk.Button open_in_browser_button;
    [GtkChild] private Gtk.Button refresh_button;

    // fullscreen headerbar controls
    [GtkChild] private Gtk.HeaderBar fs_headerbar;
    [GtkChild] private Gtk.ToggleButton fs_choose_board_button;
    [GtkChild] private Gtk.ToggleButton fs_show_search_bar_button;
    [GtkChild] private Gtk.Button fs_open_in_browser_button;
    [GtkChild] private Gtk.Button fs_refresh_button;
    [GtkChild] private Gtk.Revealer fs_revealer;

    [GtkChild] private Gtk.SearchBar searchbar;
    [GtkChild] private Gtk.Stack content_stack;
    [GtkChild] private Gtk.Notebook notebook;
    [GtkChild] private Gtk.Label no_content_description;

    // board chooser
    [GtkChild] private Gtk.Popover popover;
    [GtkChild] private Gtk.ListBox listbox;
    [GtkChild] private Gtk.SearchEntry board_search;

    private CatalogWidget catalog;

    const ActionEntry[] shortcuts = {
        { "close_tab", close_tab },
        { "toggle_search", toggle_search },
        { "next_tab", next_tab },
        { "prev_tab", prev_tab },
        { "fullscreen", toggle_fullscreen }
    };

    void close_tab () {
        var page = notebook.get_nth_page (notebook.page);
        if (page != catalog)
            page.destroy ();
    }

    void toggle_search () {
        if (!searchbar.search_mode_enabled) {
            searchbar.search_mode_enabled = true;
            searchentry.grab_focus_without_selecting ();
        } else {
            searchbar.search_mode_enabled = false;
        }
    }

    void next_tab () {
        notebook.page = (notebook.page+1) % notebook.get_n_pages ();
    }

    void prev_tab () {
        notebook.page = (notebook.page-1) % notebook.get_n_pages ();
    }

    private bool _is_fullscreen = false;
    private bool is_fullscreen {
        get { return _is_fullscreen; }
        set {
            _is_fullscreen = value;
            if (_is_fullscreen) {
                this.fullscreen ();
                popover.relative_to = fs_choose_board_button;
            } else {
                this.unfullscreen ();
                popover.relative_to = choose_board_button;
                fs_revealer.reveal_child = false;
            }
        }
    }

    void toggle_fullscreen () {
        is_fullscreen = !is_fullscreen;
    }

    public MainWindow (Gtk.Application app) {
        Object (application: app);

        add_action_entries (shortcuts, this);

        app.set_accels_for_action ("app.quit", {"<Primary>Q"});
        app.set_accels_for_action ("win.close_tab", {"<Primary>W"});
        app.set_accels_for_action ("win.toggle_search", {"<Primary>F"});
        app.set_accels_for_action ("win.next_tab", {"<Primary>Tab"});
        app.set_accels_for_action ("win.prev_tab", {"<Primary><Shift>Tab"});
        app.set_accels_for_action ("win.fullscreen", {"F11"});

        Variant geom = App.settings.get_value ("win-geom");
        int x, y, width, height;
        geom.get ("(iiii)", out x, out y, out width, out height);
        move (x, y);
        set_default_size (width, height);

        // meme magic:
        const string[] no_content_texts = {
            "Select a board to begin",
            "Select a board to waste time on",
            "Select a board to shitpost about animu",
            "Start wasting time",
            "Get out of your mom's basement"
        };

        no_content_description.label = no_content_texts [Random.int_range (0, no_content_texts.length)];

        App.settings.changed["filter-nsfw-content"].connect (listbox.invalidate_filter);
        board_search.changed.connect (listbox.invalidate_filter);

        FourChan.get_boards.begin ((obj, res) => {
            var boards = FourChan.get_boards.end (res);
            listbox.foreach (w => w.destroy ());
            foreach (Board b in boards) {
                var row = new Gtk.Label ("/%s/ - %s".printf (b.board, b.title));
                row.name = b.board;
                row.margin = 6;
                row.halign = Gtk.Align.START;
                row.set_data ("nsfw", b.ws_board == 0);
                listbox.add (row);
            }
            listbox.show_all ();
        });

        listbox.set_filter_func (row => {
            var label = row.get_child () as Gtk.Label;
            if (App.settings.get_boolean ("filter-nsfw-content") && label.get_data ("nsfw"))
                return false;
            if (board_search.text == "")
                return true;
            return label.name.contains (board_search.text);
        });

        notebook.page_added.connect ((w, p) =>
            notebook.show_tabs = (notebook.get_n_pages() > 1));
        notebook.page_removed.connect ((w, p) =>
            notebook.show_tabs = (notebook.get_n_pages() > 1));

        show_search_bar_button.bind_property ("active", searchbar, "search-mode-enabled", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        fs_show_search_bar_button.bind_property ("active", searchbar, "search-mode-enabled", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        fs_open_in_browser_button.bind_property ("sensitive", open_in_browser_button, "sensitive", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        fs_refresh_button.bind_property ("sensitive", refresh_button, "sensitive", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        fs_choose_board_button.bind_property ("label", choose_board_button, "label", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        notebook.notify["page"].connect ((obj, pspec) => {
            NotebookPage page = notebook.get_nth_page (notebook.page) as NotebookPage;
            headerbar.title = page.name;
            fs_headerbar.title = page.name;

            if (page.search_text != null && page.search_text != "") {
                searchbar.search_mode_enabled = true;
                searchentry.text = page.search_text;
            } else {
                searchbar.search_mode_enabled = false;
            }
        });

        listbox.row_selected.connect (row => {
            if (row != null) { // why is it null?
                var child = row.get_child () as Gtk.Label;
                FourChan.board = child.name;

                open_in_browser_button.sensitive = false;
                refresh_button.sensitive = false;
                choose_board_button.label = child.label;

                popover.visible = false;
                board_search.text = "";

                content_stack.visible_child = notebook;
                notebook.page = notebook.page_num (catalog);
            }
        });

        catalog = new CatalogWidget ();
        add_page (catalog, false, false);

        FourChan.catalog.downloaded.connect ((o, board, threads) => {
            catalog.clear ();
            foreach (Page page in threads)
                foreach (ThreadOP t in page.threads)
                    catalog.add (this, t);
            open_in_browser_button.sensitive = true;
            refresh_button.sensitive = true;
        });

        this.show_all ();
    }

    public override bool delete_event (Gdk.EventAny ev) {
        int x, y, width, height;
        get_position (out x, out y);
        get_size (out width, out height);
        App.settings.set ("win-geom", "(iiii)", x, y, width, height);
        return false;
    }

    public void show_thread (int64 no, Gdk.Pixbuf op_thumbnail) {
        var panelview = new PanelView ();
        var threadpane = new ThreadPane (FourChan.board, no, op_thumbnail);
        var thread = new Thread (FourChan.board, no);
        threadpane.set_model (thread);

        panelview.name = "Loading…";
        FourChan.dl_thread.begin (thread, (obj, res) => {
            FourChan.dl_thread.end (res);
            panelview.name = thread.get_title ();
        });

        panelview.add (threadpane);
        add_page (panelview);
    }

    private void add_page (NotebookPage page, bool closeable = true, bool reorderable = true) {
        var tab = new Tab (notebook, page, closeable);
        int i = notebook.append_page (page, tab);
        notebook.child_set (page, "reorderable", reorderable);
        notebook.set_current_page (i);

        page.notify["name"].connect (() => {
            notebook.notify_property ("page");
        });
    }

    [GtkCallback]
    private void open_in_browser (Gtk.Button button) {
        var current = notebook.get_nth_page (notebook.page);
        assert (current is NotebookPage);
        ((NotebookPage) current).open_in_browser ();
    }

    [GtkCallback]
    private void search_entry_changed (Gtk.Editable entry) {
        var current = notebook.get_nth_page (notebook.page);
        var text = ((Gtk.Entry) entry).text;
        assert (current is NotebookPage);
        ((NotebookPage) current).search_text = text;
    }

    [GtkCallback]
    private void refresh (Gtk.Button button) {
        var current = notebook.get_nth_page (notebook.page);
        assert (current is NotebookPage);
        ((NotebookPage) current).refresh ();
    }

    [GtkCallback]
    private void restore (Gtk.Button button) {
        is_fullscreen = false;
    }

    private bool in_fs_controls = false;

    [GtkCallback]
    private bool fs_controls_enter (Gdk.EventCrossing event) {
        if (!is_fullscreen)
            return Gdk.EVENT_PROPAGATE;
        fs_revealer.reveal_child = true;
        in_fs_controls = true;
        return Gdk.EVENT_STOP;
    }

    [GtkCallback]
    private bool fs_controls_leave (Gdk.EventCrossing event) {
        in_fs_controls = false;
        if (!fs_choose_board_button.active)
            fs_revealer.reveal_child = false;
        return Gdk.EVENT_PROPAGATE;
    }

    [GtkCallback]
    private void fs_choose_board_button_cb () {
        fs_revealer.reveal_child = fs_choose_board_button.active || in_fs_controls;
    }
}
