import argparse
import time
from threading import Thread

import matplotlib.pyplot as plt

import pysoem

THREAD_ITERATIONS = 40
READ_ITERATIONS = 50
times = []

slave = None
_release_gil = None

def show_plot(y_data):
    x_data = list(range(len(y_data)))
    last_point = len(y_data) - 1
    middle_point = len(y_data) // 2
    m = (y_data[last_point] - y_data[middle_point]) / (
        x_data[last_point] - x_data[middle_point]
    )
    b = y_data[last_point] - m * x_data[last_point]
    # Calculates the lineal equation with the last point and the middle point

    fig, ax = plt.subplots()
    ax.plot(x_data, y_data, "o")
    ax.plot(
        [0, x_data[last_point]], [b, y_data[last_point]], label=f"y={m:.4f}x+{b:.4f}"
    )
    ax.set(xlabel="N", ylabel="time (s)")
    ax.legend()
    ax.grid()
    plt.show()


def thread_func():
    for _ in range(READ_ITERATIONS):
        status_word = slave.sdo_read(0x1018, 1, _release_gil)


def main(interface_name: str, release_gil: bool):
    global slave
    global _release_gil
    master = pysoem.Master()
    master.open(interface_name)
    master.config_init()
    slave = master.slaves[0]
    _release_gil = release_gil
    thread_instance = Thread(target=thread_func)
    thread_instance.start()
    for _ in range(THREAD_ITERATIONS):
        times.append(time.time())
        time.sleep(0.005)
    thread_instance.join()
    times_with_0 = [(x - times[0]) for x in times]
    show_plot(times_with_0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Release GIL example")
    parser.add_argument(
        "-i", "--interface_name", help="Interface nme", type=str, required=True
    )
    parser.add_argument(
        "-g", "--nogil", help="If present, GIL will be released", action="store_true"
    )
    args = parser.parse_args()
    main(interface_name=args.interface_name, release_gil=args.nogil)