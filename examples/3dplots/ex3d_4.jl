# This file was generated, do not modify it. # hide
using Gnuplot
x = y = -15:0.33:15
fz(x,y) = sin.(sqrt.(x.^2 + y.^2))./sqrt.(x.^2+y.^2)
fxy = [fz(x,y) for x in x, y in y]
@gsp " " :-  # reset session
@gsp(x, y, fxy, "w l lc palette", "set view map",
    "set contour base;set key off","set auto fix",
    "set cntrparam levels 15", "unset surface",
    xlab = "x", ylab = "y")
save(term="pngcairo size 800,800", output="plt3d_ex4.png")