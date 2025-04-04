FROM ocaml/opam:debian-11-ocaml-4.05


# Dependencies
USER root
RUN apt update && apt-get install -y --no-install-recommends\
    ca-certificates \
    curl wget\
    build-essential \
#    opam \
    python2 \
    ocaml-findlib \
    libffi-dev \
    mpi-default-dev \
    pkg-config \
    git rsync mercurial darcs\
    libgmp-dev\
    time\
    bison flex\
    && apt-get clean


# remove new versions of openmpi
RUN apt-get remove --purge openmpi-bin libopenmpi-dev -y
# link 'python' to 'python2' 
RUN ln -s /usr/bin/python2 /usr/bin/python

# Change ownership
WORKDIR /bymc-deps
RUN chown -cR opam:opam /bymc-deps
RUN chown -cR opam:opam /home/opam
USER opam

### OCAML
# archived dependencies
RUN opam repository add archive git+https://github.com/ocaml/opam-repository-archive
# opam dependencies
RUN opam install -y\
    batteries=2.9.0 \
    ocamlgraph=1.8.8 \
    sexplib=v0.13.0 \
    ctypes=0.14.0\
    ctypes-foreign=0.4.0\
    lazy-trie=1.2.0\
    z3=4.7.1\
    menhir=20180528\
    ounit=2.0.8\
    num


### OPENMPI < 3.0.0
# download
RUN wget https://download.open-mpi.org/release/open-mpi/v2.1/openmpi-2.1.6.tar.gz
RUN tar -xzf openmpi-2.1.6.tar.gz
WORKDIR /bymc-deps/openmpi-2.1.6
# build
RUN ./configure --prefix=/usr/local/openmpi-2.1.6
RUN make -j10 all
# install
USER root
# install
RUN make install
# adjust path
ENV PATH=/usr/local/openmpi-2.1.6/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/openmpi-2.1.6/lib:$LD_LIBRARY_PATH


### OCAMLMPI
# download
USER opam
WORKDIR /bymc-deps
RUN wget https://github.com/xavierleroy/ocamlmpi/archive/refs/tags/rel103.tar.gz
RUN tar -xzf rel103.tar.gz
WORKDIR /bymc-deps/ocamlmpi-rel103
# Modify the Makefile to set the required variables
RUN sed -i "s|MPIINCDIR=.*|MPIINCDIR=/usr/local/openmpi-2.1.6/include|" Makefile
RUN sed -i "s|MPILIBDIR=.*|MPILIBDIR=/usr/local/openmpi-2.1.6/lib|" Makefile
RUN sed -i "s|MPICC=.*|MPICC=/usr/local/openmpi-2.1.6/bin/mpicc|" Makefile
RUN sed -i "s|MPIRUN=.*|MPIRUN=/usr/local/openmpi-2.1.6/bin/mpirun|" Makefile
# build
RUN eval $(opam env) && make -j10 all opt
# install
USER root
RUN make install
# adjust path
ENV OCAMLPATH=/usr/local/lib/ocaml/4.11.1:$OCAMLPATH


### BYMC
USER opam
WORKDIR /bymc
RUN git clone https://github.com/konnov/bymc.git
WORKDIR /bymc/bymc/bymc
RUN eval $(opam env) && make -j10 


### Z3
# The opam installation for some reason fails to create the shared library. Even 
# though there are no errors upon compilation, the manual build & install is 
# necessary
WORKDIR /bymc-deps
RUN wget https://github.com/Z3Prover/z3/archive/z3-4.7.1.tar.gz
RUN tar -xzf z3-4.7.1.tar.gz
WORKDIR /bymc-deps/z3-z3-4.7.1
RUN eval $(opam env) && python2 scripts/mk_make.py --ml
WORKDIR /bymc-deps/z3-z3-4.7.1/build
RUN eval $(opam env) && make -j10
# installation
USER root 
RUN  eval $(opam env) && make install 
USER opam


WORKDIR /bymc/bymc
ENTRYPOINT [ "/bin/bash" ]
