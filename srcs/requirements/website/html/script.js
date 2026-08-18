document.addEventListener("DOMContentLoaded", () => {

    const navbar = document.querySelector(".navbar");

    window.addEventListener("scroll", () => {

        if (window.scrollY > 30) {
            navbar.style.background = "rgba(6, 9, 15, 0.92)";
        } else {
            navbar.style.background = "rgba(8, 11, 18, 0.72)";
        }

    });

});
