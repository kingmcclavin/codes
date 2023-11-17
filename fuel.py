import sys
def main():
    frac = input("Fraction: ")
    while True:
        if ((frac.find("/")) > 0):
            x, y = frac.split("/")
        else:
            frac = input("Fraction: ")
        while True:
            if ((x.isnumeric()) and (y.isnumeric())):
                x = int(x)
                y = int(y)
                while True:
                    if (y == 0):
                        frac = input("Fraction: ")
                    elif ((x / y) <= 1):
                        sepperate(x, y)
                        break
                    else:
                        frac = input("Fraction: ")
            else:
                frac = input("Fraction: ")

def sepperate(x, y):
    x = int(x)
    y = int(y)
    p = (x / y)
    if (.9 >= p >= .2):
        p = str(round((p * 100), 0))
        sys.exit((p[0:2]) + "%")
    elif (p == 1) or (p > .9):
        sys.exit("F")
    elif (p == 0) or (p < .02):
        sys.exit("E")

main()
