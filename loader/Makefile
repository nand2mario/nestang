
OBJ := nes_loader.o osd.o util.o

loader: $(OBJ)
	g++ -o loader $(OBJ)

%.o: %.cpp
	g++ -std=c++17 -c $< -o $@

clean:
	rm -rf *.o loader