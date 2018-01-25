FROM jenkins:1.651.2

# Install custom set of plugins
COPY plugins.txt /plugins.txt
RUN /usr/local/bin/plugins.sh /plugins.txt

USER root

# Enable passwordless sudo for jenkins and set timezone
RUN echo "Etc/UTC" > /etc/timezone
RUN dpkg-reconfigure -f noninteractive tzdata
RUN apt-get update && apt-get install -y sudo libunwind8 libicu52 && rm -rf /var/lib/apt/lists/*
RUN sed -i.bkp -e \
      's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' \
      /etc/sudoers
RUN usermod --append --groups sudo jenkins

# Create log directory
RUN mkdir /var/log/jenkins
RUN chown -R jenkins:jenkins /var/log/jenkins

# Create cache directory
RUN mkdir /var/cache/jenkins
RUN chown -R jenkins:jenkins /var/cache/jenkins

USER jenkins

# Enable STARTTLS
ENV JAVA_OPTS "-Djava.awt.headless=true -Dmail.smtp.starttls.enable=true"

# Enable HTTPs for the web interface
ENV JENKINS_OPTS "--handlerCountStartup=100 --handlerCountMax=300 --logfile=/var/log/jenkins/jenkins.log --webroot=/var/cache/jenkins/war --httpPort=8080 --httpsPort=8443 --httpsCertificate=/var/jenkins_home/ssl/cert.pem --httpsPrivateKey=/var/jenkins_home/ssl/key.pem"
EXPOSE 8443
