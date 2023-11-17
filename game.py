import random
import sys

def main():
    c = 0
    x = ""
    while x == "":
        x = input("Level: ")
        if x.isalpha():
            x = ""
            pass
        elif (x.isnumeric()):
            x = int(x)
            if (1 <= x <= 10000000000):
                a = random.randint(1, x)
                break
            else:
                x = ""
    g = ""
    while g != a:
        g = input("Guess: ")
        if g.isalpha():
           c = c + 1
           pass
        elif g.isnumeric():
            g = int(g)
            if g < a:
                c = c + 1
                print("Too Small!")
            elif g > a:
               print("Too Large!")
               c = c + 1
            elif g == a:
                c = c + 1
                print("Just Right!")
                print("Guesses:", c)
                break
        else:
             pass

main()