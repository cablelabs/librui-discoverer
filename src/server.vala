/* Copyright (c) 2014, CableLabs, Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */
using Gee;
using GUPnP;
using Soup;

struct Icon {
    uint64? width;
    uint64? height;
    string url;
}

struct RemoteUI {
    string? id;
    string? name;
    string? description;
    Icon[]? icons;
    string? url;
}

internal class RuiHttpServer {
    class ServiceMap {
        private Map<string, RemoteUI?> byId;
        private MultiMap<string, RemoteUI?> byService;
        private Gee.List<RemoteUI?> inOrder;

        public ServiceMap() {
            byId = new HashMap<string, RemoteUI?>();
            byService = new HashMultiMap<string, RemoteUI?>();
            inOrder = new ArrayList<RemoteUI?>();
        }

        public void add(ServiceProxy service, RemoteUI ui) {
            byId.set(ui.id, ui);
            byService.set(service.udn, ui);
            for (var i = 0; i < inOrder.size; i++) {
                if (inOrder[i].id == ui.id) {
                    inOrder[i] = ui;
                    return;
                }
            }
            inOrder.add(ui);
        }

        public void remove(ServiceProxy service) {
            foreach (RemoteUI ui in byService.get(service.udn)) {
                byId.unset(ui.id);
                for (var i = 0; i < inOrder.size; i++) {
                    if (inOrder[i].id == ui.id) {
                        inOrder.remove_at(i);
                        break;
                    }
                }
            }
            byService.remove_all(service.udn);
        }

        public Collection<RemoteUI?> uis {
            owned get {
                return inOrder;
            }
        }
    }

    static int port = 0;
    static bool debug = false;

    static const OptionEntry[] options = {
        { "port", 'p', 0, OptionArg.INT, ref port,
            "The port to run the HTTP server on. By default, the server picks a random available port.", "[port]" },
        { "debug", 'd', 0, OptionArg.NONE, ref debug,
            "Print debug messages to the console", null },
        { null }
    };

    ServiceMap services;

    RuiHttpServer() {
        services = new ServiceMap();
    }

    static string? get_url_from_xml(Xml.Node* node, Soup.URI base_url, string name) {
        for (Xml.Node* child = node->children; child != null; child = child->next) {
            if (child->name != name) {
                continue;
            }
            string url = child->get_content();
            url = new Soup.URI.with_base(base_url, url).to_string(false);
            return url;
        }
        return null;
    }

    void handle_compatible_uis(ServiceProxy service,
            ServiceProxyAction action) {
        Soup.URI base_url = service.get_url_base();
        try {
            string ui_listing;
            service.end_action(action,
                /* out */
                "UIListing", typeof(string), out ui_listing,
                null);
            if (ui_listing == null) {
                stderr.printf("Got null UI listing from %s.\n",
                    base_url.to_string(false));
                return;
            }
            Xml.Doc* doc = Xml.Parser.parse_memory(ui_listing, ui_listing.length);
            if (doc == null) {
                stderr.printf("Got bad UI listing from %s.\n",
                    base_url.to_string(false));
                if (debug) {
                    stderr.printf("  Content was: %s\n", ui_listing);
                }
                return;
            }
            Xml.Node* root = doc->get_root_element();
            if (root == null) {
                stderr.printf("UI listing from %s has no elements.\n",
                    base_url.to_string(false));
                if (debug) {
                    stderr.printf("  Content was: %s\n", ui_listing);
                }
                delete doc;
                return;
            }
            if (root->name != "uilist") {
                stderr.printf("UI listing from %s doesn't start with a <uilist> element\n",
                    base_url.to_string(false));
                if (debug) {
                    stderr.printf("  Content was: %s\n", ui_listing);
                }
                delete doc;
                return;
            }
            for (Xml.Node* ui_element = root->children; ui_element != null; ui_element = ui_element->next) {
                if (ui_element->name != "ui") {
                    continue;
                }
                RemoteUI ui = RemoteUI();
                ui.icons = {};
                for (Xml.Node* child = ui_element->children; child != null; child = child->next) {
                    switch (child->name) {
                        case "uiID":
                            ui.id = child->get_content();
                            break;
                        case "name":
                            ui.name = child->get_content();
                            break;
                        case "description":
                            ui.description = child->get_content();
                            break;
                        case "iconList":
                            // TODO: Pick the best icon instead of the first one
                            for (Xml.Node* icon_node = child->children; icon_node != null; icon_node = icon_node->next) {
                                if (icon_node->name != "icon") {
                                    continue;
                                }
                                Icon icon = {};
                                icon.url = get_url_from_xml(icon_node,
                                    base_url, "url");
                                if (icon.url == null) {
                                    if (debug) {
                                        stderr.printf("Ignoring icon with no URL.\n");
                                    }
                                    continue;
                                }
                                for (Xml.Node* icon_child = icon_node->children; icon_child != null; icon_child = icon_child->next) {
                                    switch(icon_child->name) {
                                        case "width":
                                            var width = icon_child->get_content();
                                            icon.width = long.parse(width);
                                            if (icon.width == 0) {
                                                icon.width = null;
                                            }
                                            break;
                                        case "height":
                                            var height = icon_child->get_content();
                                            icon.height = long.parse(height);
                                            if (icon.height == 0) {
                                                icon.height = null;
                                            }
                                            break;
                                    }
                                }
                                ui.icons += icon;
                            }
                            break;
                        case "protocol":
                            // TODO: Make sure this has shortName="DLNA-HTML5-1.0" ?
                            ui.url = get_url_from_xml(child, base_url,
                                "uri");
                            break;
                    }
                }
                services.add(service, ui);
                if (debug) {
                    stdout.printf("Discovered server \"%s\" at %s from %s\n",
                        ui.name, ui.url, service.udn);
                }
            }

            delete doc;
        } catch (Error e) {
            stderr.printf("Error from GetCompatibleUIs from %s: %s\n",
                base_url.to_string(false), e.message);
            return;
        }
    }

    void service_proxy_available(ControlPoint control_point,
            ServiceProxy service) {
        service.begin_action("GetCompatibleUIs", handle_compatible_uis,
            /* in */
            "InputDeviceProfile", typeof(string), "",
            "UIFilter", typeof(string), "",
            null);
    }

    void service_proxy_unavailable(ControlPoint control_point,
            ServiceProxy service) {
        if (debug) {
            stdout.printf("Service unavailable %s\n", service.udn);
        }
        services.remove(service);
    }

    void handle_rui_request(Server server, Message message, string path,
            HashTable? query, ClientContext context) {
        Json.Builder builder = new Json.Builder();
        builder.begin_array();
        foreach (RemoteUI ui in services.uis) {
            builder.begin_object();
            builder.set_member_name("id");
            builder.add_string_value(ui.id);
            builder.set_member_name("name");
            builder.add_string_value(ui.name);
            builder.set_member_name("url");
            builder.add_string_value(ui.url);
            builder.set_member_name("icons");
            builder.begin_array();
            foreach (Icon icon in ui.icons) {
                builder.begin_object();
                builder.set_member_name("url");
                builder.add_string_value(icon.url);
                if (icon.width != null) {
                    builder.set_member_name("width");
                    builder.add_int_value((int64)icon.width);
                }
                if (icon.height != null) {
                    builder.set_member_name("height");
                    builder.add_int_value((int64)icon.height);
                }
                builder.end_object();
            }
            builder.end_array();
            builder.end_object();
        }
        builder.end_array();
        
        Json.Generator generator = new Json.Generator();
        generator.set_pretty(true);
        generator.set_root(builder.get_root());
        string data = generator.to_data(null);
        message.set_status(Soup.Status.OK);
        message.set_response("application/json", MemoryUse.COPY, data.data);
    }
    
    void handle_static_file(Server server, Message message, string path,
            HashTable? query, ClientContext context) {
        server.pause_message(message);
        handle_static_file_async.begin(server, message, path, query, context);
    }

    async void handle_static_file_async(Server server, Message message, string path,
            HashTable? query, ClientContext context) {
        if (path == "/" || path == "") {
            path = "index.html";
        }
        var file = File.new_for_path("static/" + path);
        try {
            var info = yield file.query_info_async("*", FileQueryInfoFlags.NONE);
            var io = yield file.read_async();
            Bytes data;
            while ((data = yield io.read_bytes_async((size_t)info.get_size())).length > 0) {
                message.response_body.append(MemoryUse.COPY, data.get_data());
            }
            string content_type = info.get_content_type();
            message.set_status(Soup.Status.OK);
            message.response_headers.set_content_type(content_type, null);
        } catch (IOError.NOT_FOUND e) {
            message.set_status(404);
            message.set_response("text/plain", MemoryUse.COPY,
                ("File " + file.get_path() + " does not exist.").data);
        } catch (Error e) {
            if (debug) {
                stderr.printf("Failed to read file %s: %s\n", file.get_path(),
                    e.message);
            }
            message.set_status(500);
            message.set_response("text/plain", MemoryUse.COPY, e.message.data);
        } finally {
            server.unpause_message(message);
        }
    }

    void start() throws Error{
        Context context = new Context(null, null, 0);

        ControlPoint control_point = new ControlPoint(context,
            "urn:schemas-upnp-org:service:RemoteUIServer:1");
        control_point.service_proxy_available.connect(service_proxy_available);
        control_point.service_proxy_unavailable.connect(service_proxy_unavailable);
        control_point.set_active(true);

        stdout.printf(
            "Starting UPnP server on %s:%u\n", context.host_ip, context.port);

        Server server = new Server(SERVER_PORT, port, null);
        server.add_handler(null, handle_static_file);
        server.add_handler("/api/remote-uis", handle_rui_request);
        server.run_async();
        stdout.printf("Starting HTTP server on http://localhost:%u\n",
            server.port);

        MainLoop loop = new MainLoop();
        loop.run();
    }

    static int main(string[] args) {
        try {
            var opt_context = new OptionContext("RUI Discovery Server");
            opt_context.set_help_enabled (true);
            opt_context.add_main_entries (options, null);
            opt_context.parse (ref args);
        } catch (OptionError e) {
            stderr.printf ("%s\n", e.message);
            stderr.printf ("Run '%s --help' to see a full list of available command line options.\n",
                args[0]);
            return 2;
        }
        try {
            RuiHttpServer server = new RuiHttpServer();
            server.start();
        } catch (Error e) {
            stderr.printf("Error running RuiHttpServer: %s\n", e.message);
            return 1;
        }
        return 0;
    }
}
