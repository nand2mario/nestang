
OBJ := nes_loader.o osd.o util.o

# Link libstdc++ statically: https://web.archive.org/web/20160313071116/http://www.trilithium.com/johan/2005/06/static-libstdc/
loader: $(OBJ)
	g++ -static-libgcc -static-libstdc++ -o loader $(OBJ)

%.o: %.cpp
	g++ -std=c++17 -c $< -o $@

clean:
	rm -rf *.o loader