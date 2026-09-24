# syntax=docker/dockerfile:1.7
ARG DOME_BASE_IMAGE=dome-docker-base:kilted
FROM ${DOME_BASE_IMAGE}

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ARG ROS_DISTRO=kilted
ENV ROS_DISTRO=${ROS_DISTRO}
ARG DOME_USER=robot
ARG DOME_PASSWORD=""
ENV DOME_HOME=/home/${DOME_USER}

COPY manifest/ /manifest/

RUN useradd -m -s /bin/bash "${DOME_USER}" && \
    if [[ -n "${DOME_PASSWORD}" ]]; then echo "${DOME_USER}:${DOME_PASSWORD}" | chpasswd; fi && \
    usermod -aG sudo "${DOME_USER}" && \
    echo "${DOME_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${DOME_USER} && \
    chmod 0440 /etc/sudoers.d/${DOME_USER} && \
    while IFS= read -r d; do mkdir -p "${DOME_HOME}/${d}"; done < /manifest/dirs.txt && \
    touch "${DOME_HOME}/.bash_history" && \
    chmod 600 "${DOME_HOME}/.bash_history" && \
    chown -R "${DOME_USER}:${DOME_USER}" "${DOME_HOME}"
WORKDIR ${DOME_HOME}

RUN mkdir -p -m 0700 /root/.ssh && ssh-keyscan github.com >> /root/.ssh/known_hosts

RUN --mount=type=ssh \
    set -euo pipefail; \
    source /manifest/lib.sh; \
    clone_section() { \
      local section="$1"; \
      local base_dir="$2"; \
      mkdir -p "${base_dir}"; \
      while read -r line; do \
        [[ -z "${line}" ]] && continue; \
        manifest_parse_repo "${line}"; \
        echo "Cloning ${REPO_URL} -> ${base_dir}/${REPO_DEST}"; \
        if [[ -n "${REPO_BRANCH}" ]]; then \
          git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${base_dir}/${REPO_DEST}" || { echo "ERROR: failed to clone ${REPO_URL}"; exit 1; }; \
        else \
          git clone "${REPO_URL}" "${base_dir}/${REPO_DEST}" || { echo "ERROR: failed to clone ${REPO_URL}"; exit 1; }; \
        fi; \
      done < <(awk -v s="${section}" '$0=="["s"]"{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/ && NF' /manifest/repos.txt); \
    }; \
    clone_section root "${DOME_HOME}"; \
    clone_section root-pi "${DOME_HOME}"; \
    clone_section ros_ws "${DOME_HOME}/ros2_ws/src"; \
    clone_section uros_ws "${DOME_HOME}/uros_ws/src"; \
    chown -R "${DOME_USER}:${DOME_USER}" "${DOME_HOME}"

USER root
RUN if [[ -f "${DOME_HOME}/ros2_ws/src/dome_vision/dome_vision/pyproject.toml" ]]; then \
      rm -f "${DOME_HOME}/ros2_ws/src/dome_vision/dome_vision/setup.py"; \
      pip3 install --break-system-packages "${DOME_HOME}/ros2_ws/src/dome_vision/dome_vision/"; \
    fi


RUN find "${DOME_HOME}/ros2_ws/src" -type d \
      \( -name build -o -name install -o -name log -o -name prefix_override -o -name __pycache__ -o -name .pytest_cache \) \
      -prune -exec rm -rf {} + && \
    find "${DOME_HOME}/ros2_ws/src" -type d -name "*.egg-info" -prune -exec rm -rf {} + && \
    rosdep update && \
    cd "${DOME_HOME}/ros2_ws" && \
    skip_keys=$(awk -F'=[[:space:]]*' '/^skip_keys/{print $2}' /manifest/rosdep.txt) && \
    rosdep install --from-paths src --ignore-src -r -y --skip-keys="$skip_keys" && \
    chown -R "${DOME_USER}:${DOME_USER}" "${DOME_HOME}"
USER ${DOME_USER}

RUN source /opt/ros/${ROS_DISTRO}/setup.bash && \
    cd "${DOME_HOME}/ros2_ws" && \
    flags=$(awk -F'=[[:space:]]*' '/^flags/{print $2}' /manifest/colcon.txt) && \
    skip=$(awk -F'=[[:space:]]*' '/^packages_skip/{print $2}' /manifest/colcon.txt) && \
    colcon build $flags --packages-skip $skip

COPY manifest/bashrc ${DOME_HOME}/.bashrc
RUN if [[ -f "${DOME_HOME}/rosutils/bru.py" ]]; then ln -s "${DOME_HOME}/rosutils/bru.py" "${DOME_HOME}/.local/bin/bru" && chmod +x "${DOME_HOME}/rosutils/bru.py"; fi

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/install-optional-deps.sh /usr/local/bin/install-optional-deps.sh
USER root
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/install-optional-deps.sh
USER ${DOME_USER}
WORKDIR ${DOME_HOME}/ros2_ws

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash"]
