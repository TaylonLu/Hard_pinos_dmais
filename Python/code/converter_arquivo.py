import numpy as np

with open("sigmoid/digit_3.txt", "r") as f:
    pixels = [int(line.strip(), 16) for line in f.readlines()]

with open("sigmoid/W_in_q.txt", "r") as f:
    pesos = [int(line.strip(), 16) for line in f.readlines()]

with open("sigmoid/b_q.txt", "r") as f:
    bias = [int(line.strip(), 16) for line in f.readlines()]
    
with open("sigmoid/beta_q.txt", "r") as f:
    beta = [int(line.strip(), 16) for line in f.readlines()]

pixels = pixels[:784]
pesos = pesos[:100352]
bias = bias[:128]
beta = beta[:1280]

with open("Convertido/digit_3.hex", "w") as f:
    for p in pixels:
        f.write("{:04X}\n".format(p & 0xFFFF))

with open("Convertido/W_in_q.hex", "w") as f:
    for w in pesos:
        f.write("{:04X}\n".format(w & 0xFFFF))

with open("Convertido/b_q.hex", "w") as f:
    for b_q in bias:
        f.write("{:04X}\n".format(b_q & 0xFFFF))

with open("Convertido/beta_q.hex", "w") as f:
    for b in beta:
        f.write("{:04X}\n".format(b & 0xFFFF))