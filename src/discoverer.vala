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
public class RUI.Discoverer {

    public struct Service {
        string id;
        string base_url;
        string ui_listing;
    }

    bool debug = false;
    private Gee.Map<string, Service?> _services;
    GUPnP.ControlPoint control_point;

    public Gee.Collection<Service?> services {
        owned get {
            return _services.values;
        }
    }

    public signal void services_changed();

    public Discoverer(bool debug) {
        this.debug = debug;
        _services = new Gee.HashMap<string, Service?>();
    }

    void handle_compatible_uis(GUPnP.ServiceProxy service,
            GUPnP.ServiceProxyAction action) {
        string base_url = service.get_url_base().to_string(false);
        try {
            string ui_listing;
            service.end_action(action,
                /* out */
                "UIListing", typeof(string), out ui_listing,
                null);
            if (ui_listing == null) {
                stderr.printf("Got null UI listing from %s.\n", base_url);
                return;
            }
            _services.set(service.udn, {service.udn, base_url, ui_listing});
            services_changed();
        } catch (Error e) {
            stderr.printf("Error from GetCompatibleUIs from %s: %s\n",
                base_url, e.message);
            return;
        }
    }

    void service_proxy_available(GUPnP.ControlPoint control_point,
            GUPnP.ServiceProxy service) {
        service.begin_action("GetCompatibleUIs", handle_compatible_uis,
            /* in */
            "InputDeviceProfile", typeof(string), "",
            "UIFilter", typeof(string), "",
            null);
    }

    void service_proxy_unavailable(GUPnP.ControlPoint control_point,
            GUPnP.ServiceProxy service) {
        if (debug) {
            stdout.printf("Service unavailable %s\n", service.udn);
        }
        _services.unset(service.udn);
        services_changed();
    }

    public void start() throws Error{
        var context = new GUPnP.Context(null, null, 0);

        control_point = new GUPnP.ControlPoint(context,
            "urn:schemas-upnp-org:service:RemoteUIServer:1");
        control_point.service_proxy_available.connect(service_proxy_available);
        control_point.service_proxy_unavailable.connect(
            service_proxy_unavailable);
        control_point.set_active(true);

        stdout.printf(
            "Starting UPnP server on %s:%u\n", context.host_ip, context.port);
    }
}
