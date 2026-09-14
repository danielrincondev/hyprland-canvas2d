package.path = "./hypr/?.lua;./hypr/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Test = require("tests.testlib")

require("tests.geometry_test")(Test)
require("tests.engine_test")(Test)
require("tests.row_scroll_test")(Test)
require("tests.adapter_test")(Test)

Test.run()
