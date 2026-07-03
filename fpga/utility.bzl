def _res_1_1000(os_name, inputs_num): return {"cpu": 1, "memory": 1000}
def _res_1_2000(os_name, inputs_num): return {"cpu": 1, "memory": 2000}
def _res_2_2000(os_name, inputs_num): return {"cpu": 2, "memory": 2000}
def _res_2_4000(os_name, inputs_num): return {"cpu": 2, "memory": 4000}
def _res_4_4000(os_name, inputs_num): return {"cpu": 4, "memory": 4000}
def _res_4_8000(os_name, inputs_num): return {"cpu": 4, "memory": 8000}
def _res_8_8000(os_name, inputs_num): return {"cpu": 8, "memory": 8000}
def _res_8_16000(os_name, inputs_num): return {"cpu": 8, "memory": 16000}
def _res_12_12000(os_name, inputs_num): return {"cpu": 12, "memory": 12000}
def _res_16_16000(os_name, inputs_num): return {"cpu": 16, "memory": 16000}

def get_resource_set(cpu, memory):
    if cpu <= 1:
        if memory <= 1000:
            return _res_1_1000
        return _res_1_2000
    elif cpu <= 2:
        if memory <= 2000:
            return _res_2_2000
        return _res_2_4000
    elif cpu <= 4:
        if memory <= 4000:
            return _res_4_4000
        return _res_4_8000
    elif cpu <= 8:
        if memory <= 8000:
            return _res_8_8000
        return _res_8_16000
    elif cpu <= 12:
        return _res_12_12000
    else:
        return _res_16_16000
