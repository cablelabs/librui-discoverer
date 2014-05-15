#!/usr/bin/env python3
import os
import string

CURRENT_DIR = os.path.dirname(os.path.realpath(__file__))
NAME = "rui-discoverer"
PREFIX = "/usr/local"
VERSION = [str(i) for i in (1, 0, 0)]
VERSION_STR = ".".join(VERSION)
MAJOR_VERSION = ".".join(VERSION[:2])

# Remove annoying tup stuff from path
if "@tupjob" in CURRENT_DIR:
    begin = CURRENT_DIR.find("@tupjob")
    begin = CURRENT_DIR.find("/", begin)
    CURRENT_DIR = CURRENT_DIR[begin:]

with open("../pkgconfig/%s-%s.pc.in" % (NAME, MAJOR_VERSION), "r") as f:
    template = f.read();
#with open("../pkgconfig/%s-%s.pc" % (NAME, MAJOR_VERSION), "w") as f:
#    f.write(string.Template(template).substitute(name=NAME, prefix=PREFIX,
#        version=VERSION_STR, major_version=MAJOR_VERSION, include="/include",
#        lib="/lib"))
with open("../pkgconfig/%s-%s.pc" % (NAME, MAJOR_VERSION), "w") as f:
    f.write(string.Template(template).substitute(name=NAME,
        prefix=os.path.join(CURRENT_DIR, "..", "src"),
        version=VERSION_STR, major_version=MAJOR_VERSION, include="", lib=""))

