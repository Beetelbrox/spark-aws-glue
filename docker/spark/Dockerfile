ARG SPARK_VERSION=3.1.1
ARG HADOOP_VERSION=3.2.0
ARG HIVE_VERSION=2.3.7
ARG MAVEN_VERSION=3.6.3
ARG SCALA_VERSION=2.12
ARG AWS_JAVA_SDK_VERSION=1.11.797
ARG SPARK_HOME=/opt/spark

# Stage 0: Build dependencies
FROM maven:${MAVEN_VERSION}-openjdk-8 AS  build-deps
RUN apt-get update \
    && apt-get install -y patch wget
# Configure the pentaho nexus repo as the default one doesnt' work
COPY build/maven-settings.xml ${MAVEN_HOME}/conf/settings.xml

# Stage 1: Build patched Hive
FROM build-deps AS build-hive
# Import args into the stage
ARG HIVE_VERSION

RUN mkdir /opt/hive
WORKDIR /opt/hive
RUN wget https://github.com/apache/hive/archive/rel/release-${HIVE_VERSION}.tar.gz -O /tmp/hive.tar.gz \
    && tar xzf /tmp/hive.tar.gz --strip-components=1 -C /opt/hive \
    && wget https://issues.apache.org/jira/secure/attachment/12958418/HIVE-12679.branch-2.3.patch \
    && patch -p0 <HIVE-12679.branch-2.3.patch \
    && mvn clean install -DskipTests

# Stage 2: Build glue catalog client for hive
FROM build-hive AS build-glue-client-for-hive
# Import args into the stage
ARG HIVE_VERSION
ARG HADOOP_VERSION
ARG AWS_JAVA_SDK_VERSION

# Build the patched hive client. This is like 3 forks away from the original aws-labs client to make it
# work w/ Spark 3
RUN git clone https://github.com/viaduct-ai/aws-glue-data-catalog-client-for-apache-hive-metastore /catalog
WORKDIR /catalog
RUN mvn clean package \
    -DskipTests \
    -Dhive2.version=${HIVE_VERSION} \
    -Dhadoop.version=${HADOOP_VERSION} \
    -Daws.sdk.version=${AWS_JAVA_SDK_VERSION} \
    -pl -aws-glue-datacatalog-hive2-client
RUN mkdir /catalog/output-jars \
    && find /catalog -name "*.jar" | grep -Ev "test|original" | xargs -I{} cp {} /catalog/output-jars

# Stage 3: Build spark using the patched Hive
FROM build-glue-client-for-hive AS build-spark
# Import args into the stage
ARG HADOOP_VERSION
ARG HIVE_VERSION
ARG SCALA_VERSION
ARG SPARK_VERSION

WORKDIR /opt
ENV MAKEFLAGS -j 4
# Build Spark
RUN git clone https://github.com/apache/spark.git --branch v${SPARK_VERSION} --single-branch && \
    cd /opt/spark && \
    ./dev/make-distribution.sh \
    --name spark \
    -DskipTests \
    -P"hadoop-${HADOOP_VERSION%.*}" \
    -Dhadoop.version="${HADOOP_VERSION}" \
    -Dhive.version="${HIVE_VERSION}" \
    -Phive

# Stage 4: Build spark base image
FROM openjdk:8 AS spark-base
# Import args into the stage
ARG AWS_JAVA_SDK_VERSION
ARG HADOOP_VERSION
ARG SPARK_HOME
ARG SPARK_JARS=${SPARK_HOME}/jars

COPY --from=build-spark /opt/spark/dist ${SPARK_HOME}/
COPY --from=build-glue-client-for-hive /catalog/output-jars ${SPARK_JARS}/
COPY conf ${SPARK_HOME}/conf
# Add the glue client to the jars, get an updated version of the aws-java-sdk bundle & update Guava to a
# compatible version. This is copied from one of the repos and I'm not sure if it's even needed.
RUN wget --quiet https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/${AWS_JAVA_SDK_VERSION}/aws-java-sdk-bundle-${AWS_JAVA_SDK_VERSION}.jar -P ${SPARK_JARS}/
RUN chmod 0644 ${SPARK_JARS}/aws-java-sdk-bundle*.jar
RUN rm -f ${SPARK_JARS}/guava-14.0.1.jar
RUN wget --quiet https://repo1.maven.org/maven2/com/google/guava/guava/23.0/guava-23.0.jar -P ${SPARK_JARS}/
RUN chmod 0644 ${SPARK_JARS}/guava-23.0.jar
RUN wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar -P ${SPARK_HOME}/jars/

# Stage 5: Output stage
FROM openjdk:8 AS spark-output
ARG SPARK_HOME
ENV SPARK_HOME=${SPARK_HOME}

RUN useradd -ms /bin/bash spark
COPY --from=spark-base --chown=spark ${SPARK_HOME} ${SPARK_HOME}
ENV PATH "${PATH}:${SPARK_HOME}/bin"
USER spark
