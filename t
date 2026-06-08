diff --git a/inkcut/device/plugin.py b/inkcut/device/plugin.py
index 6b30c6c..a548162 100644
--- a/inkcut/device/plugin.py
+++ b/inkcut/device/plugin.py
@@ -140,6 +140,15 @@ class DeviceProtocol(Model):
         """
         raise NotImplementedError
 
+    def set_working_area(self, working_area):
+        """ Set the working area for the device.
+         Parameters
+        ----------
+        working_area["x0"] Lower left x coordinate.
+        working_area["y0"] Lower left y coordinate.
+        working_area["x1"] Upper right x coordinate.
+        working_area["y1"] Upper right y coordinate.
+        """
     def set_pen(self, p):
         """ Set the pen or tool that should be used.
 
@@ -310,6 +319,11 @@ class DeviceConfig(Model):
     force_units = Enum('g').tag(config=True)
     force_enabled = Bool().tag(config=True)
 
+    # Whether or not to send a 'window' command
+    # to the plotter causing it to clip the
+    # plot to the area of the page or device, whichever is smaller.
+    clip_output_to_page = Bool().tag(config = True)
+
     #: Use absolute coordinates
     absolute = Bool().tag(config=True)
 
@@ -793,6 +807,24 @@ class Device(Model):
 
                         self.status = "Working..."
 
+                        if config.clip_output_to_page:
+                            # Calculate the effective working area
+                            # and inform the device through the protocol
+                            # if it supports it.  Some protocols
+                            # may ignore this.
+                            x0 = self.job.material.padding_left
+                            y0 = self.job.material.padding_bottom
+                            x1 = min(self.job.material.width() - self.job.material.padding_right, self.area.width())
+                            y1 = min(self.job.material.height() - self.job.material.padding_top, self.area.height())
+                            working_area = {
+                                "x0": x0,
+                                "y0": y0,
+                                "x1": x1,
+                                "y1": y1
+                            }
+                            yield defer.maybeDeferred(
+                                protocol.set_working_area, working_area)
+
                         if config.force_enabled:
                             yield defer.maybeDeferred(
                                 protocol.set_force, config.force)
diff --git a/inkcut/device/protocols/camm.py b/inkcut/device/protocols/camm.py
index cbb6b12..3149f11 100644
--- a/inkcut/device/protocols/camm.py
+++ b/inkcut/device/protocols/camm.py
@@ -14,6 +14,9 @@ class CAMMGL1Protocol(DeviceProtocol):
     def move(self, x, y, z, absolute=True):
         self.write("{z}{x},{y};".format(x=x, y=y, z=z and "D" or "M", ))
         
+    def set_working_area(self, bounding_box):
+        pass
+
     def set_force(self, f):
         self.write("FS{f};".format(f=f))
         
diff --git a/inkcut/device/protocols/debug.py b/inkcut/device/protocols/debug.py
index d123ae3..8fc95c5 100644
--- a/inkcut/device/protocols/debug.py
+++ b/inkcut/device/protocols/debug.py
@@ -7,7 +7,6 @@ Created on Oct 23, 2015
 from inkcut.device.plugin import DeviceProtocol
 from inkcut.core.utils import async_sleep, log
 
-
 class DebugProtocol(DeviceProtocol):
     """ A protocol that just logs what is called """
     def connection_made(self):
@@ -24,6 +23,9 @@ class DebugProtocol(DeviceProtocol):
     def set_velocity(self, v):
         log.debug("protocol.set_velocity({v})".format(v=v))
         
+    def set_working_area(self, bounding_box):
+        pass
+
     def set_force(self, f):
         log.debug("protocol.set_force({f})".format(f=f))
 
@@ -31,4 +33,4 @@ class DebugProtocol(DeviceProtocol):
         log.debug("protocol.data_received({}".format(data))
 
     def connection_lost(self):
-        log.debug("protocol.connection_lost()")
\ No newline at end of file
+        log.debug("protocol.connection_lost()")
diff --git a/inkcut/device/protocols/dmpl.py b/inkcut/device/protocols/dmpl.py
index 8f4e944..8130b96 100644
--- a/inkcut/device/protocols/dmpl.py
+++ b/inkcut/device/protocols/dmpl.py
@@ -35,6 +35,17 @@ class DMPLProtocol(DeviceProtocol):
         elif v == 6:
             self.write("IN;PA;")
 
+    def set_working_area(self, bounding_box):
+        # This is un-tested in DMPL, but this should be
+        # the correct command if anyone wants to test
+        # it and put it in here.
+        #x0 = int(self.scale * bounding_box["x0"])
+        #y0 = int(self.scale * bounding_box["y0"])
+        #x1 = int(self.scale * bounding_box["x1"])
+        #y1 = int(self.scale * bounding_box["y1"])
+        #self.write(" W %i,%i,%i,%i,%i,%i,%i,%i " % (x0, y0, x1, y1, x0, y0, x1, y1))
+        pass
+
     def move(self, x, y, z, absolute=True):
         x, y = int(x*self.scale), int(y*self.scale)
         v = self.config.mode
diff --git a/inkcut/device/protocols/gcode.py b/inkcut/device/protocols/gcode.py
index 6a5bef8..c3d25c3 100644
--- a/inkcut/device/protocols/gcode.py
+++ b/inkcut/device/protocols/gcode.py
@@ -80,6 +80,9 @@ class GCodeProtocol(DeviceProtocol):
         line += "\n"
         self.write(line)
 
+    def set_working_area(self, bounding_box):
+        pass
+
     def set_force(self, f):
         raise NotImplementedError
         
@@ -95,4 +98,4 @@ class GCodeProtocol(DeviceProtocol):
             self.write("G98; Return to initial z\n")
 
     def connection_lost(self):
-        pass
\ No newline at end of file
+        pass
diff --git a/inkcut/device/protocols/gpgl.py b/inkcut/device/protocols/gpgl.py
index 28af3f8..5a04b58 100644
--- a/inkcut/device/protocols/gpgl.py
+++ b/inkcut/device/protocols/gpgl.py
@@ -17,6 +17,9 @@ class GPGLProtocol(DeviceProtocol):
     def move(self, x, y, z, absolute=True):
         self.write("%s%i,%i"%('D' if z else 'M', x, y))
 
+    def set_working_area(self, bounding_box):
+        pass
+
     def set_velocity(self, v):
         self.write('!%i' % v)
 
diff --git a/inkcut/device/protocols/hpgl.py b/inkcut/device/protocols/hpgl.py
index d48f4e5..22b4e7d 100644
--- a/inkcut/device/protocols/hpgl.py
+++ b/inkcut/device/protocols/hpgl.py
@@ -41,6 +41,13 @@ class HPGLProtocol(DeviceProtocol):
         else:
             self.write('PR%i,%i;' % (x, y))
 
+    def set_working_area(self, bounding_box):
+        x0 = int(self.scale * bounding_box["x0"])
+        y0 = int(self.scale * bounding_box["y0"])
+        x1 = int(self.scale * bounding_box["x1"])
+        y1 = int(self.scale * bounding_box["y1"])
+        self.write("IW%i,%i,%i,%i;" % (x0, y0, x1, y1))
+
     def set_force(self, f):
         self.write("FS%i; " % f)
         
diff --git a/inkcut/device/view.enaml b/inkcut/device/view.enaml
index 195c8d2..fa9f7d1 100644
--- a/inkcut/device/view.enaml
+++ b/inkcut/device/view.enaml
@@ -66,6 +66,12 @@ enamldef DeviceConfigView(Container):
                 CheckBox:
                     text = QApplication.translate("device", "Enabled")
                     checked := model.force_enabled
+
+                Label:
+                    text = QApplication.translate("device", "Device Clipping (if supported by device)")
+                CheckBox:
+                    text = QApplication.translate("device", "Enabled")
+                    checked := model.clip_output_to_page
         Page:
             closable = False
             title = QApplication.translate("device", "Output")
