# This file was generated, do not modify it. # hide
using Gnuplot
x = y = -15:0.33:15
fz(x,y) = sin.(sqrt.(x.^2 + y.^2))./sqrt.(x.^2+y.^2)
fxy = [fz(x,y) for x in x, y in y]
@gsp " " :-  # reset session
@gsp(:-,x, y, fxy, "w pm3d", "set ylabel 'y' textcolor rgb 'red'",
    "set xlabel 'x' textcolor rgb 'blue'")
save(term="pngcairo size 800,800", output="plt3d_ex3_1.png")