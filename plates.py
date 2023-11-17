def main():
    plate = input("Plate: ")
    if is_valid(plate):
        print("Valid")
    else:
        print("Invalid")


def is_valid(s):
    if letters(s) and amount(s) and numcheck(s) and punc(s):
        return True
    else:
        return False

def letters(s):
    if s[0:2].isalpha():
        return True
    else:
        return False

def amount(s):
    if (len(s) >= 2) and (len(s) <= 6):
        return True
    else:
        return False

def numcheck(s):
    g = False
    k = 0
    x = len(s)
    for i in range (x):
        if (s[i].isnumeric()):
            if (s[i] == "0" and g == False):
                return False
            k = i
            g = True
            while k < len(s):
                if s[k].isalpha():
                    return False
                k = k + 1
    return True


def punc(s):
    x = len(s)
    for i in range (x):
        if (s[i] == ".") or (s[i] == " ") or (s[i] == "!") or (s[i] == ","):
            return False
    return True

main()