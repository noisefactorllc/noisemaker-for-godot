search synth, filter

noise(_id: "source").invert(_id: "filter").write(o1, _id: "saved")
read(surface: o1, _id: "input").write(o0, _id: "output")
render(o0)
