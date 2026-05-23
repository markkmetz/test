import tkinter as tk

def toggle_button():
    if button.cget("text") == "Start":
        button.config(text="Stop", bg="red")
    else:
        button.config(text="Start", bg="SystemButtonFace")

root = tk.Tk()
root.title("Toggle Button")

button = tk.Button(root, text="Start", command=toggle_button)
button.pack(padx=20, pady=20)

root.mainloop()
