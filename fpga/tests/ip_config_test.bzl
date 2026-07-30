load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//fpga:providers.bzl", "FpgaIpInfo")
load("//fpga:rules.bzl", "fpga_ip_config")

# Test default behavior (ooc = True)
def _ip_config_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)
    asserts.true(env, FpgaIpInfo in target_under_test, "FpgaIpInfo provider should be returned")
    
    info = target_under_test[FpgaIpInfo]
    asserts.equals(env, "uart_ctrl", info.entity_name)
    asserts.equals(env, "u_uart_debug", info.instance_name)
    asserts.equals(env, "115200", info.generics.get("BAUD_RATE"))
    asserts.equals(env, "some_val", info.memory_mapping)
    asserts.true(env, info.ooc, "ooc should default to True")
    
    return analysistest.end(env)

ip_config_test = analysistest.make(
    impl = _ip_config_test_impl,
)

# Test explicitly setting ooc = False
def _ip_config_no_ooc_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)
    asserts.true(env, FpgaIpInfo in target_under_test)
    
    info = target_under_test[FpgaIpInfo]
    asserts.false(env, info.ooc, "ooc should be False when explicitly set to False")
    
    return analysistest.end(env)

ip_config_no_ooc_test = analysistest.make(
    impl = _ip_config_no_ooc_test_impl,
)

def ip_config_test_suite(name):
    # 1. Define targets under test
    fpga_ip_config(
        name = "test_ip_config_target",
        entity_name = "uart_ctrl",
        instance_name = "u_uart_debug",
        generics = {
            "BAUD_RATE": "115200",
        },
        memory_mapping = "some_val",
        tags = ["manual"],
    )

    fpga_ip_config(
        name = "test_ip_config_no_ooc_target",
        entity_name = "uart_ctrl",
        instance_name = "u_uart_gps",
        generics = {
            "BAUD_RATE": "9600",
        },
        ooc = False,
        tags = ["manual"],
    )
    
    # 2. Define tests
    ip_config_test(
        name = name + "_test",
        target_under_test = ":test_ip_config_target",
    )

    ip_config_no_ooc_test(
        name = name + "_no_ooc_test",
        target_under_test = ":test_ip_config_no_ooc_target",
    )
