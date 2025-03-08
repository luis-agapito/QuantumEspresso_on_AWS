FROM amazonlinux:latest
RUN yum -y update
RUN yum -y install unzip which 
ENV NOTVISIBLE "in users profile"

#####################################################
## LAPACK
RUN yum -y install wget tar gzip gcc gcc-gfortran make
RUN wget -O /tmp/lapack.tar.gz http://www.netlib.org/lapack/lapack-3.8.0.tar.gz
RUN tar -xvf /tmp/lapack.tar.gz -C /tmp
RUN cd /tmp/lapack-3.8.0 && cp make.inc.example make.inc && make blaslib && make cblaslib && \
    make lib && cp libcblas.a liblapack.a librefblas.a libtmglib.a /usr/local/lib/

#####################################################
## OPENMPI
RUN yum -y install openmpi openmpi-devel
ENV PATH $PATH:/usr/lib64/openmpi/bin
ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:/usr/local/lib/:/usr/lib64/openmpi/lib

#####################################################
## SCALAPACK
RUN wget -O /tmp/scalapack.tgz http://www.netlib.org/scalapack/scalapack-2.0.2.tgz
RUN tar -xvf /tmp/scalapack.tgz -C /tmp
RUN cd /tmp/scalapack-2.0.2 && cp SLmake.inc.example SLmake.inc && \
    sed -i 's/FCFLAGS       = -O3/FCFLAGS       = -O3 -fallow-argument-mismatch/g' SLmake.inc && \
    make lib && cp libscalapack.a /usr/local/lib
#fortran: Error: Type mismatch between actual argument at (1) and actual argument at (2)
#add flag -fallow-argument-mismatch

#####################################################
## FFTW 
RUN wget -O /tmp/fftw.tar.gz http://www.fftw.org/fftw-3.3.8.tar.gz
RUN tar -xvf /tmp/fftw.tar.gz -C /tmp
RUN cd /tmp/fftw-3.3.8 && ./configure --prefix=/usr/local && make all && make install

#####################################################
## QE 6.5
RUN wget -O /tmp/q-e.tar.gz https://github.com/QEF/q-e/archive/qe-6.5.tar.gz
RUN tar -xvf /tmp/q-e.tar.gz -C /tmp
RUN cd /tmp/q-e-qe-6.5 && \
    ./configure --prefix=/usr/local/ BLAS_LIBS="-L/usr/local/lib -lrefblas" && \
    sed -i 's/FFLAGS         = -O3 -g/FFLAGS         = -O3 -g -fallow-argument-mismatch/g' make.inc && \
    make pw && make install
#LAPACK_LIBS="-L/usr/local/lib -llapack"
#fortran: Error: Type mismatch between actual argument at (1) and actual argument at (2)
#add flag -fallow-argument-mismatch

RUN rm -rf /tmp/*

#####################################################
## SSH SETUP
ENV USER root
RUN mkdir -p /var/run/sshd
RUN yum -y install iproute openssh-server openssh-clients 
RUN sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

RUN echo "export VISIBLE=now" >> /etc/profile

RUN echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
ENV SSHDIR /root/.ssh
RUN mkdir -p ${SSHDIR} RUN touch ${SSHDIR}/sshd_config
RUN ssh-keygen -t rsa -f ${SSHDIR}/ssh_host_rsa_key -N ''
RUN cp ${SSHDIR}/ssh_host_rsa_key.pub ${SSHDIR}/authorized_keys
RUN cp ${SSHDIR}/ssh_host_rsa_key ${SSHDIR}/id_rsa
RUN echo "   IdentityFile ${SSHDIR}/id_rsa" >> /etc/ssh/ssh_config
RUN echo "   StrictHostKeyChecking no" >> /etc/ssh/ssh_config
RUN chmod -R 600 ${SSHDIR}/* && \
    chown -R ${USER}:${USER} ${SSHDIR}/
# check if ssh agent is running or not, if not, run
RUN eval `ssh-agent -s` && ssh-add ${SSHDIR}/id_rsa

##################################################
## S3 OPTIMIZATION
RUN yum -y install python python-pip
RUN pip install awscli 
RUN aws configure set default.s3.max_concurrent_requests 30
RUN aws configure set default.s3.max_queue_size 10000
RUN aws configure set default.s3.multipart_threshold 64MB
RUN aws configure set default.s3.multipart_chunksize 16MB
RUN aws configure set default.s3.max_bandwidth 4096MB/s
RUN aws configure set default.s3.addressing_style path

RUN aws configure set default.region us-east-2

##################################################
## supervisor container startup
RUN pip install supervisor 
ADD ./supervisord.conf /files/supervisord.conf
ADD ./mpi-run.sh /files/mpi-run.sh
RUN chmod 755 /files/mpi-run.sh

EXPOSE 22
RUN export PATH="$PATH:/opt/openmpi/bin"
ADD ./entry-point.sh /files/entry-point.sh
RUN chmod 0755 /files/entry-point.sh
ADD ./scf.in /tmp/scf.in
ADD ./Si.pz-vbc.UPF /tmp/Si.pz-vbc.UPF

CMD /files/entry-point.sh
