using Gee;
using GUPnP;
using Soup;

internal class RuiHttpServer {
    struct RemoteUI {
        string id;
        string name;
        string description;
        string iconUrl;
        string url;
    }

    HashMap<string, RemoteUI?> remoteUis;

    RuiHttpServer() {
        remoteUis = new HashMap<string, RemoteUI?>();
    }

    void handle_compatible_uis(ServiceProxy service, ServiceProxyAction action) {
        try {
            string ui_listing;
            service.end_action(action,
                /* out */
                "UIListing", typeof(string), out ui_listing,
                null);
            Xml.Doc* doc = Xml.Parser.parse_memory(ui_listing, ui_listing.length);
            if (doc == null) {
                stderr.printf("Got bad UI listing.\n");
                return;
            }
            Xml.Node* root = doc->get_root_element();
            if (root == null) {
                stderr.printf("UI listing has no elements.\n");
                delete doc;
                return;
            }
            if (root->name != "uilist") {
                stderr.printf("UI listing doesn't start with a <uilist> element\n");
                delete doc;
                return;
            }
            for (Xml.Node* ui_element = root->children; ui_element != null; ui_element = ui_element->next) {
                if (ui_element->name != "ui") {
                    continue;
                }
                RemoteUI ui = RemoteUI();
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
                            bool found = false;
                            for (Xml.Node* icon = child->children; !found && icon != null; icon = icon->next) {
                                if (icon->name != "icon") {
                                    continue;
                                }
                                for (Xml.Node* ichild = icon->children; ichild != null; ichild = ichild->next) {
                                    if (ichild->name == "url") {
                                        ui.iconUrl = ichild->get_content();
                                        if (ui.iconUrl != null & ui.iconUrl.length > 0 && ui.iconUrl[0] == '/') {
                                            ui.iconUrl = new Soup.URI.with_base(service.get_url_base(), ui.iconUrl).to_string(false);
                                        }
                                        found = true;
                                        break;
                                    }
                                }
                            }
                            break;
                        case "protocol":
                            // TODO: Make sure this has shortName="DLNA-HTML5-1.0" ?
                            for (Xml.Node* pchild = child->children; pchild != null; pchild = pchild->next) {
                                if (pchild->name == "uri") {
                                    ui.url = pchild->get_content();
                                    if (ui.url != null & ui.url.length > 0 && ui.url[0] == '/') {
                                        ui.url = new Soup.URI.with_base(service.get_url_base(), ui.url).to_string(false);
                                    }
                                }
                            }
                            break;
                    }
                }
                remoteUis.set(ui.id, ui);
            }

            delete doc;
        } catch (Error e) {
            stderr.printf("Error from GetCompatibleUIs: %s\n", e.message);
            return;
        }
    }

    void service_proxy_available(ControlPoint control_point, ServiceProxy service) {
        service.begin_action("GetCompatibleUIs", handle_compatible_uis,
            /* in */
            "InputDeviceProfile", typeof(string), "",
            "UIFilter", typeof(string), "",
            null);
    }

    void handle_rui_request(Server server, Message message, string path, HashTable? query, ClientContext context) {
        Json.Builder builder = new Json.Builder();
        builder.begin_array();
        foreach (RemoteUI ui in remoteUis.values) {
            builder.begin_object();
            builder.set_member_name("id");
            builder.add_string_value(ui.id);
            builder.set_member_name("name");
            builder.add_string_value(ui.name);
            builder.set_member_name("url");
            builder.add_string_value(ui.url);
            builder.set_member_name("iconUrl");
            builder.add_string_value(ui.iconUrl);
            builder.end_object();
        }
        builder.end_array();
        
        Json.Generator generator = new Json.Generator();
        generator.set_pretty(true);
        generator.set_root(builder.get_root());
        string data = generator.to_data(null);
        message.set_response("application/json", MemoryUse.COPY, data.data);
    }
    
    void handle_static_file(Server server, Message message, string path, HashTable? query, ClientContext context) {
        if (path == "/" || path == "") {
            path = "index.html";
        }
        var file = File.new_for_path("static/" + path);
        if (!file.query_exists()) {
            message.set_status(404);
            message.set_response("text/plain", MemoryUse.COPY, ("File " + file.get_path() + " does not exist.").data);
            return;
        }
        try {
            var io = file.read();
            var info = file.query_info("*", FileQueryInfoFlags.NONE);
            var data = io.read_bytes((size_t)info.get_size());
            string content_type = info.get_content_type();
            message.set_response(content_type, MemoryUse.COPY, data.get_data());
        } catch (Error e) {
            message.set_status(500);
            message.set_response("text/plain", MemoryUse.COPY, e.message.data);
        }
    }

    void start() throws Error{
        Context context = new Context(null, null, 0);

        ControlPoint control_point = new ControlPoint(context, "urn:schemas-upnp-org:service:RemoteUIServer:1");
        control_point.service_proxy_available.connect(service_proxy_available);
        control_point.set_active(true);

        stdout.printf("Starting DLNA Remote UI server service server on %s:%u\n", context.host_ip, context.port);

        Server server = new Server(SERVER_PORT, 0, null);
        server.add_handler(null, handle_static_file);
        server.add_handler("/api/remote-uis", handle_rui_request);
        server.run_async();
        stdout.printf("Starting HTTP server on  http://localhost:%u\n", server.port);

        MainLoop loop = new MainLoop();
        loop.run();
    }

    static int main(string[] args) {
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
