onbreak {quit -f}
onerror {quit -f}

vsim -t 1ps -lib xil_defaultlib TAG_RAM_opt

do {wave.do}

view wave
view structure
view signals

do {TAG_RAM.udo}

run -all

quit -force
