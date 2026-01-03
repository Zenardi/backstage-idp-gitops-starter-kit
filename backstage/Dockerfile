FROM node:18-bookworm-slim
 
#
# Install TechDocs dependencies
#
RUN apt-get update && apt-get install -y python3 python3-pip python3-venv
 
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
 
RUN pip3 install mkdocs-techdocs-core
