from PIL import Image
import numpy as np

image_path = "Arquivos/archive/mnist_png/test/0/3.png"
mif_path = "imagem_zero.mif"

WIDTH = 16
DEPTH = 784  # 28x28

img = Image.open(image_path).convert('L')
img = img.resize((28, 28))

pixels = np.array(img)

pixels_16 = (pixels.astype(np.uint16) * 257)

pixels_flat = pixels_16.flatten()

with open(mif_path, "w") as f:
    f.write(f"WIDTH={WIDTH};\n")
    f.write(f"DEPTH={DEPTH};\n\n")
    f.write("ADDRESS_RADIX=UNS;\n")
    f.write("DATA_RADIX=HEX;\n\n")
    f.write("CONTENT BEGIN\n")

    for i, pixel in enumerate(pixels_flat):
        hex_value = format(int(pixel), '04X')  # 4 dígitos HEX
        f.write(f"{i} : {hex_value};\n")

    f.write("END;\n")
